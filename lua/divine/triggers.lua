---@alias divine.KeyMode 'n'|'x'|'s'|'i'|'t'|'o'
---@alias divine.Cleanup fun(id: divine.NodeId)
---@alias divine.Activate fun()
---@alias divine.ModuleSearcher fun(name: string): (fun(): any)|string

---@class divine.KeyTrigger
---@field lhs string Nonempty key sequence; expanded after startup configuration.
---@field mode? divine.KeyMode Defaults to normal mode.

---@class divine.Triggers
---@field events? string[] Canonical native Neovim event names from the compiler.
---@field commands? string[] Full user-command names.
---@field filetypes? string[] Exact filetype names.
---@field keys? divine.KeyTrigger[]
---@field modules? string[] Exact module names or dotted namespace prefixes.

---@class divine.TriggerNode
---@field triggers? divine.Triggers

---@class divine.TriggerController
---@field load fun(id: divine.NodeId)

-- Startup FileType replay synthesizes this context without an autocmd ID/group.
---@class divine.ReplayContext
---@field id? integer
---@field group? integer
---@field event string
---@field match string
---@field buf integer
---@field file? string
---@field data? any Event payload is supplied by Neovim or the caller.

---@alias divine.EventContext divine.ReplayContext|vim.api.keyset.create_autocmd.callback_args

local M = {}

---@param message string
---Always raises; no successful return.
---@return nil
local function fail(message) error("divine triggers: " .. message, 0) end
---@param value any Untrusted trigger list, validated before registration.
---@param label string
---@return nil
local function list(value, label)
  if type(value) ~= "table" or not vim.islist(value) then fail(label .. " must be a list") end
  for _, item in ipairs(value) do
    if type(item) ~= "string" or item == "" then
      fail(label .. " entries must be nonempty strings")
    end
  end
end

---@class divine.EventReplay
---@field event string
---@field excluded? table<integer, boolean> Nil means dispatch every group.

---@param event string
---@return divine.EventReplay[]
local function snapshot(event)
  local events = { event }
  if event == "BufReadPost" then events = { "BufReadPre", event } end
  if event == "FileType" then events = { "BufReadPre", "BufReadPost", event } end
  ---@type divine.EventReplay[]
  local result = {}
  for _, name in ipairs(events) do
    ---@type divine.EventReplay
    local entry = { event = name }
    if name ~= "FileType" then
      entry.excluded = {}
      for _, item in ipairs(vim.api.nvim_get_autocmds({ event = name })) do
        if item.group then entry.excluded[item.group] = true end
      end
    end
    result[#result + 1] = entry
  end
  return result
end

---@param entries divine.EventReplay[]
---@param args divine.EventContext
---@return nil
local function replay(entries, args)
  vim.api.nvim_buf_call(args.buf, function()
    for _, entry in ipairs(entries) do
      ---@type vim.api.keyset.exec_autocmds
      local options = { modeline = false, data = args.data }
      if entry.event == args.event then
        options.pattern = args.match
      else
        options.buffer = args.buf
      end
      if entry.excluded then
        -- Snapshot eligible groups before dispatch: handlers may mutate the list.
        local groups, seen = {}, {}
        for _, item in ipairs(vim.api.nvim_get_autocmds({ event = entry.event })) do
          if item.group and not entry.excluded[item.group] and not seen[item.group] then
            seen[item.group] = true
            groups[#groups + 1] = item.group
          end
        end
        for _, group in ipairs(groups) do
          options.group = group
          vim.api.nvim_exec_autocmds(entry.event, options)
        end
      else
        vim.api.nvim_exec_autocmds(entry.event, options)
      end
    end
  end)
end

---@param controller divine.TriggerController Only load(node_id) is required.
---@param nodes table<divine.NodeId, divine.TriggerNode>
---@return divine.Cleanup cleanup Removes a node's remaining trigger stubs.
---@return divine.Activate activate Installs pending keys and handles open filetypes once.
function M.register(controller, nodes)
  if
    type(controller) ~= "table"
    or type(controller.load) ~= "function"
    or type(nodes) ~= "table"
  then
    fail("register requires a controller and nodes")
  end
  local ids = vim.tbl_keys(nodes)
  table.sort(ids)
  ---@type table<string, boolean>, table<string, boolean>, boolean
  local commands, keys, has_modules = {}, {}, false
  -- Validate the full registration before changing editor state.
  for _, id in ipairs(ids) do
    if type(nodes[id]) ~= "table" then fail("node " .. tostring(id) .. " must be a table") end
    local triggers = nodes[id].triggers or {}
    if type(triggers) ~= "table" then fail("triggers must be a table") end
    for kind, values in pairs(triggers) do
      if kind == "keys" then
        if type(values) ~= "table" or not vim.islist(values) then fail("keys must be a list") end
        for _, key in ipairs(values) do
          if type(key) ~= "table" or type(key.lhs) ~= "string" or key.lhs == "" then
            fail("keys require lhs")
          end
          for field in pairs(key) do
            if field ~= "lhs" and field ~= "mode" then fail("unknown key field " .. field) end
          end
          local mode = key.mode or "n"
          if not vim.tbl_contains({ "n", "x", "s", "i", "t", "o" }, mode) then
            fail("unsupported key mode " .. tostring(mode))
          end
          local signature = mode .. ":" .. key.lhs
          if keys[signature] then fail("key conflict: " .. key.lhs) end
          keys[signature] = true
        end
      elseif vim.tbl_contains({ "events", "commands", "filetypes", "modules" }, kind) then
        list(values, kind)
        if kind == "modules" and #values > 0 then has_modules = true end
        for _, value in ipairs(values) do
          if kind == "events" and vim.fn.exists("##" .. value) ~= 1 then
            fail("unknown event " .. value)
          end
          if kind == "commands" then
            if not value:match("^[A-Z][A-Za-z0-9]*$") then fail("invalid command " .. value) end
            if commands[value] or vim.fn.exists(":" .. value) == 2 then
              fail("command conflict: " .. value)
            end
            commands[value] = true
          end
        end
      else
        fail("unknown trigger kind " .. tostring(kind))
      end
    end
  end
  -- The compiler supplies canonical event identities. Keep the plan unchanged.
  ---@type table<divine.NodeId, table<string, boolean>>
  local node_events = {}
  for _, id in ipairs(ids) do
    local triggers = nodes[id].triggers or {}
    local events = {}
    for _, event in ipairs(triggers.events or {}) do
      events[event] = true
    end
    node_events[id] = events
  end
  ---@type table<divine.NodeId, (fun())[]>, table<divine.NodeId, boolean>, table<string, boolean>
  local cleaners, pending, module_busy = {}, {}, {}
  ---@type divine.ModuleSearcher
  local searcher
  ---@param id divine.NodeId
  ---@return nil
  local function cleanup(id)
    if not pending[id] then return end
    pending[id] = nil
    for _, remove in ipairs(cleaners[id]) do
      remove()
    end
  end
  ---@param id divine.NodeId
  ---@return nil
  local function load(id)
    cleanup(id)
    controller.load(id)
  end
  ---@type table<string, boolean>
  local event_busy = {}
  ---@type table<divine.NodeId, boolean>
  local reserved = {}
  ---@param targets divine.NodeId[]
  ---@param attempt fun(id: divine.NodeId)
  ---@return nil
  local function load_batch(targets, attempt)
    -- Suppress nested event dispatch without deleting unattempted stubs. A
    -- failed load is terminal, but unrelated targets must remain reachable.
    for _, id in ipairs(targets) do
      reserved[id] = true
    end
    local ok, err = pcall(function()
      for _, id in ipairs(targets) do
        -- A dependency or SCC peer may already have cleaned this target.
        if pending[id] then attempt(id) end
      end
    end)
    for _, id in ipairs(targets) do
      reserved[id] = nil
    end
    if not ok then error(err, 0) end
  end
  ---@param args divine.EventContext
  ---@return nil
  local function on_event(args)
    if event_busy[args.event] then return end
    event_busy[args.event] = true
    local ok, err = pcall(function()
      local before, targets = snapshot(args.event), {}
      for _, id in ipairs(ids) do
        local triggers = nodes[id].triggers or {}
        if
          pending[id]
          and not reserved[id]
          and (
            node_events[id][args.event]
            or (args.event == "FileType" and vim.tbl_contains(triggers.filetypes or {}, args.match))
          )
        then
          targets[#targets + 1] = id
        end
      end
      load_batch(targets, load)
      if #targets > 0 then replay(before, args) end
    end)
    event_busy[args.event] = nil
    if not ok then error(err, 0) end
  end
  ---@type table<string, { handle: integer, count: integer }>
  local event_handles = {}
  for _, id in ipairs(ids) do
    pending[id], cleaners[id] = true, {}
    local triggers = nodes[id].triggers or {}
    local events = {}
    for event in pairs(node_events[id]) do
      events[event] = true
    end
    if #(triggers.filetypes or {}) > 0 then events.FileType = true end
    for event in pairs(events) do
      local entry = event_handles[event]
      if not entry then
        -- One dispatcher per event also preserves fail-fast behavior: Neovim
        -- continues other autocmd callbacks after reporting a Lua error.
        entry = { handle = vim.api.nvim_create_autocmd(event, { callback = on_event }), count = 0 }
        event_handles[event] = entry
      end
      entry.count = entry.count + 1
      table.insert(cleaners[id], function()
        entry.count = entry.count - 1
        if entry.count == 0 then pcall(vim.api.nvim_del_autocmd, entry.handle) end
      end)
    end
    for _, name in ipairs(triggers.commands or {}) do
      vim.api.nvim_create_user_command(name, function(args)
        load(id)
        if vim.fn.exists(":" .. name) ~= 2 then
          fail("loaded target did not define command " .. name)
        end
        local range = ""
        if args.range == 1 then range = tostring(args.line1) end
        if args.range == 2 then range = args.line1 .. "," .. args.line2 end
        -- Reparse the original raw arguments rather than joining fargs, which
        -- loses escaped whitespace, quotes and the target's nargs semantics.
        vim.cmd(args.mods .. " " .. range .. name .. (args.bang and "!" or "") .. " " .. args.args)
      end, {
        nargs = "*",
        bang = true,
        range = true,
        addr = "other",
        complete = function(_, line, cursor)
          load(id)
          return vim.fn.getcompletion(line:sub(1, cursor), "cmdline")
        end,
      })
      local stub = vim.api.nvim_get_commands({ builtin = false })[name]
      table.insert(cleaners[id], function()
        if vim.deep_equal(vim.api.nvim_get_commands({ builtin = false })[name], stub) then
          pcall(vim.api.nvim_del_user_command, name)
        end
      end)
    end
  end
  ---@param id divine.NodeId
  ---@return nil
  local function install_keys(id)
    local triggers = nodes[id].triggers or {}
    for _, key in ipairs(triggers.keys or {}) do
      local mode = key.mode or "n"
      local lhs = key.lhs
      ---@return string?
      local function callback()
        local count, register = vim.v.count, vim.v.register
        if mode == "o" then
          local ok, err = pcall(load, id)
          if not ok then
            -- An expression error alone leaves the operator pending. Report
            -- the retained failure and cancel instead of replaying the key.
            vim.api.nvim_echo({ { tostring(err), "ErrorMsg" } }, true, { err = true })
            return "<Esc>"
          end
          -- Keep the pending operator in Neovim. The leading no-op allows the
          -- same lhs to be remapped to its newly installed definition.
          return "<Ignore>" .. lhs
        end
        load(id)
        local prefix = ""
        if mode == "n" or mode == "x" then
          if register ~= '"' then prefix = '"' .. register end
          if count > 0 then prefix = prefix .. count end
        end
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes(prefix .. lhs, true, false, true),
          "mi",
          false
        )
      end
      vim.keymap.set(mode, lhs, callback, {
        silent = true,
        desc = "divine lazy trigger",
        expr = mode == "o",
        remap = mode == "o",
      })
      for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
        if mapping.callback == callback then lhs = mapping.lhs end
      end
      table.insert(cleaners[id], function()
        for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
          if mapping.callback == callback then pcall(vim.keymap.del, mode, mapping.lhs) end
        end
      end)
    end
  end
  ---@param name string
  ---@return (fun(): any)|string loader_or_error
  searcher = function(name)
    if module_busy[name] then return "\n\tdivine: recursive module lookup " .. name end
    module_busy[name] = true
    local ok, err = pcall(function()
      for _, id in ipairs(ids) do
        if pending[id] then
          for _, namespace in ipairs(nodes[id].triggers and nodes[id].triggers.modules or {}) do
            if name == namespace or name:sub(1, #namespace + 1) == namespace .. "." then
              load(id)
              break
            end
          end
        end
      end
    end)
    module_busy[name] = nil
    if not ok then error(err, 0) end
    -- Continue the existing searcher chain, which now sees prepared runtimes.
    local loaded = package.loaded[name]
    if loaded ~= nil then
      return function() return loaded end
    end
    return "\n\tdivine: no module loader (runtime preparation complete)"
  end
  -- Keep the searcher installed while it runs: removing it would shift Lua's
  -- next searcher index. It becomes inert once all nodes have been cleaned.
  if has_modules then table.insert(package.loaders, 2, searcher) end
  local activated = false
  ---@return nil
  local function activate()
    if activated then return end
    -- Startup configuration may change mapleader or install mappings. Validate
    -- every pending key against that final state before installing any stubs.
    ---@type table<string, boolean>
    local expanded = {}
    for _, id in ipairs(ids) do
      if pending[id] then
        for _, key in ipairs(nodes[id].triggers and nodes[id].triggers.keys or {}) do
          local mode = key.mode or "n"
          local signature = mode .. ":" .. vim.api.nvim_replace_termcodes(key.lhs, true, true, true)
          if expanded[signature] or vim.fn.maparg(key.lhs, mode) ~= "" then
            fail("key conflict: " .. key.lhs)
          end
          expanded[signature] = true
        end
      end
    end
    activated = true
    for _, id in ipairs(ids) do
      if pending[id] then install_keys(id) end
    end
    ---@type table<integer, string>, table<divine.NodeId, integer>
    local matches, targets = {}, {}
    local before = snapshot("FileType")
    -- Snapshot matches before any load cleans a node's other trigger stubs.
    for _, id in ipairs(ids) do
      if pending[id] then
        for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buffer) then
            local ft = vim.bo[buffer].filetype
            if vim.tbl_contains(nodes[id].triggers and nodes[id].triggers.filetypes or {}, ft) then
              matches[buffer] = ft
              targets[id] = targets[id] or buffer
            end
          end
        end
      end
    end
    local ordered = {}
    for _, id in ipairs(ids) do
      if targets[id] then ordered[#ordered + 1] = id end
    end
    event_busy.FileType = true
    local ok, err = pcall(function()
      load_batch(ordered, function(id)
        vim.api.nvim_buf_call(targets[id], function() load(id) end)
      end)
      local buffers = vim.tbl_keys(matches)
      table.sort(buffers)
      for _, buffer in ipairs(buffers) do
        replay(before, {
          event = "FileType",
          match = matches[buffer],
          buf = buffer,
          file = vim.api.nvim_buf_get_name(buffer),
        })
      end
    end)
    event_busy.FileType = nil
    if not ok then error(err, 0) end
  end
  return cleanup, activate
end

return M
