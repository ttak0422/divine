---@alias divine.KeyMode 'n'|'x'|'s'|'o'|'i'|'t'
---@alias divine.Cleanup fun(id: divine.NodeId)
---@alias divine.Activate fun()
---@alias divine.ModuleSearcher fun(name: string): (fun(): any)|string

---@class divine.KeyTrigger
---@field lhs string Nonempty key sequence; expanded after startup configuration.
---@field mode? divine.KeyMode Defaults to normal mode.

---@class divine.Triggers
---@field events? string[] Native Neovim event names.
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

-- Replay probes optional legacy fields absent from current generated metadata.
-- The callback union and group name follow nvim_get_autocmds() documentation.
---@class divine.Autocmd: vim.api.keyset.get_autocmds.ret
---@field buffer? integer
---@field nested? boolean
---@field group_name? string
---@field callback? (fun(args: divine.EventContext): any)|string

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

-- Replay only handlers installed by this load. Replaying their entire original
-- augroups would also run unrelated, already executed handlers a second time.
---@param autocmd divine.Autocmd
---@return string
local function identity(autocmd)
  return vim.inspect({
    autocmd.id,
    autocmd.group,
    autocmd.pattern,
    autocmd.buffer,
    autocmd.command,
    autocmd.callback,
  })
end

local replay_serial = 0
---@param event string
---@param args divine.EventContext
---@param before table<string, integer> Identity counts consumed during replay.
---@return nil
local function replay(event, args, before)
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = event })) do
    ---@cast autocmd divine.Autocmd
    local signature = identity(autocmd)
    if (before[signature] or 0) > 0 then
      before[signature] = before[signature] - 1
    else
      ---@type vim.api.keyset.create_autocmd
      local options = { once = true, nested = autocmd.nested or false }
      if autocmd.buffer then
        options.buffer = autocmd.buffer
      else
        options.pattern = autocmd.pattern
      end
      options.callback = function(context)
        context.id, context.group = autocmd.id, autocmd.group
        context.buf, context.event, context.match, context.data =
          args.buf, args.event, args.match, args.data
        if args.file ~= nil then context.file = args.file end
        local remove
        if type(autocmd.callback) == "function" then
          remove = autocmd.callback(context)
        elseif type(autocmd.callback) == "string" then
          remove = vim.fn[autocmd.callback](context)
        else
          -- Ex-defined handlers have no API ID; their ++once and script-local
          -- command context are not fully represented by this proposed replay.
          vim.cmd(autocmd.command)
        end
        if remove or autocmd.once then pcall(vim.api.nvim_del_autocmd, autocmd.id) end
      end
      replay_serial = replay_serial + 1
      local group = vim.api.nvim_create_augroup("divine_replay_" .. replay_serial, { clear = true })
      options.group = group
      vim.api.nvim_create_autocmd(event, options)
      ---@type vim.api.keyset.exec_autocmds
      local execution = { group = group, modeline = false, data = args.data }
      if autocmd.buffer then
        execution.buffer = args.buf
      else
        execution.pattern = args.match
      end
      local ok, err = pcall(
        vim.api.nvim_buf_call,
        args.buf,
        function() vim.api.nvim_exec_autocmds(event, execution) end
      )
      vim.api.nvim_del_augroup_by_id(group)
      if not ok then error(err, 0) end
    end
  end
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
          if not vim.tbl_contains({ "n", "x", "s", "o", "i", "t" }, mode) then
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
  ---@param id divine.NodeId
  ---@param args divine.EventContext
  ---@return nil
  local function on_event(id, args)
    ---@type table<string, integer>
    local before = {}
    for _, item in ipairs(vim.api.nvim_get_autocmds({ event = args.event })) do
      ---@cast item divine.Autocmd
      local signature = identity(item)
      before[signature] = (before[signature] or 0) + 1
    end
    load(id)
    replay(args.event, args, before)
  end
  ---@param paths table<string, boolean> Runtime paths present before loading.
  ---@param buffer integer
  ---@return nil
  local function source_ftplugins(paths, buffer)
    if vim.g.did_load_ftplugin ~= 1 then return end
    vim.api.nvim_buf_call(buffer, function()
      local did = vim.b.did_ftplugin
      vim.b.did_ftplugin = nil
      for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
        if not paths[path] then
          for ft in vim.bo.filetype:gmatch("[^.]+") do
            for _, pattern in ipairs({
              ft .. ".vim",
              ft .. ".lua",
              ft .. "_*.vim",
              ft .. "_*.lua",
              ft .. "/*.vim",
              ft .. "/*.lua",
            }) do
              for _, file in ipairs(vim.fn.globpath(path, "ftplugin/" .. pattern, false, true)) do
                vim.cmd.source(file)
              end
            end
          end
        end
      end
      vim.b.did_ftplugin = vim.b.did_ftplugin or did
    end)
  end
  ---@param id divine.NodeId
  ---@param args divine.EventContext
  ---@return nil
  local function on_filetype(id, args)
    local native_pending, seen_trigger = false, false
    for _, item in ipairs(vim.api.nvim_get_autocmds({ event = "FileType" })) do
      if args.id and item.id == args.id then seen_trigger = true end
      if seen_trigger and item.group_name == "filetypeplugin" then native_pending = true end
    end
    ---@type table<string, boolean>
    local paths = {}
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      paths[path] = true
    end
    on_event(id, args)
    -- A native loader still pending in this FileType dispatch will see the new paths.
    if not native_pending then source_ftplugins(paths, args.buf) end
  end
  for _, id in ipairs(ids) do
    pending[id], cleaners[id] = true, {}
    local triggers = nodes[id].triggers or {}
    ---@param event string
    ---@param options vim.api.keyset.create_autocmd
    ---@return nil
    local function autocmd(event, options)
      local handle = vim.api.nvim_create_autocmd(event, options)
      table.insert(cleaners[id], function() pcall(vim.api.nvim_del_autocmd, handle) end)
    end
    for _, event in ipairs(triggers.events or {}) do
      autocmd(event, { callback = function(args) on_event(id, args) end })
    end
    if #(triggers.filetypes or {}) > 0 then
      autocmd("FileType", {
        callback = function(args)
          if vim.tbl_contains(triggers.filetypes, args.match) then on_filetype(id, args) end
        end,
      })
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
      ---@return nil
      local function callback()
        local count, register, operator = vim.v.count, vim.v.register, vim.v.operator
        load(id)
        local prefix = ""
        if mode == "n" or mode == "x" or mode == "o" then
          if register ~= '"' then prefix = '"' .. register end
          if count > 0 then prefix = prefix .. count end
        end
        if mode == "o" then prefix = "<Esc>" .. prefix .. operator end
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes(prefix .. lhs, true, false, true),
          "mi",
          false
        )
      end
      vim.keymap.set(mode, lhs, callback, { silent = true, desc = "divine lazy trigger" })
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
    ---@type table<string, boolean>, table<integer, string>, table<divine.NodeId, integer>, table<string, integer>
    local paths, matches, targets, before = {}, {}, {}, {}
    for _, item in ipairs(vim.api.nvim_get_autocmds({ event = "FileType" })) do
      ---@cast item divine.Autocmd
      local signature = identity(item)
      before[signature] = (before[signature] or 0) + 1
    end
    for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
      paths[path] = true
    end
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
    for _, id in ipairs(ids) do
      local buffer = targets[id]
      if buffer and pending[id] then vim.api.nvim_buf_call(buffer, function() load(id) end) end
    end
    local buffers = vim.tbl_keys(matches)
    table.sort(buffers)
    for _, buffer in ipairs(buffers) do
      replay("FileType", {
        event = "FileType",
        match = matches[buffer],
        buf = buffer,
        file = vim.api.nvim_buf_get_name(buffer),
      }, vim.deepcopy(before))
      source_ftplugins(paths, buffer)
    end
  end
  return cleanup, activate
end

return M
