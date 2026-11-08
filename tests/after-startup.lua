-- Actual startup phases cannot be reproduced by an already-running RPC child.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local repo = vim.fn.getcwd()
local function write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(vim.split(table.concat(lines, "\n"), "\n", { plain = true }), path)
end
local ok, err = xpcall(function()
  for _, name in ipairs({
    "early",
    "late",
    "ft",
    "default",
    "native_default",
    "bad",
    "independent",
    "event",
  }) do
    local package = root .. "/packages/" .. name
    write(package .. "/plugin/main.lua", { "vim.g['" .. name .. "_plugin'] = true" })
    local emits_color = name == "early" or name == "late" or name == "ft"
    if emits_color then
      write(package .. "/colors/divine_" .. name .. ".lua", {
        "vim.g.colors_name = 'divine_" .. name .. "'",
      })
    end
    write(package .. "/after/plugin/main.lua", {
      "vim.g['" .. name .. "_after'] = (vim.g['" .. name .. "_after'] or 0) + 1",
      name == "bad" and "error('startup after fixture failed')" or "",
      emits_color and ("vim.cmd.colorscheme('divine_" .. name .. "')") or "",
    })

    -- Mirror the generated opt view: only managed after/plugin is absent.
    local target = root .. "/pack/divine/opt/" .. name
    vim.fn.mkdir(target, "p")
    for entry in vim.fs.dir(package) do
      if entry == "after" and name ~= "default" and name ~= "native_default" then
        vim.fn.mkdir(target .. "/after", "p")
        for runtime in vim.fs.dir(package .. "/after") do
          if runtime ~= "plugin" then
            assert(
              vim.uv.fs_symlink(package .. "/after/" .. runtime, target .. "/after/" .. runtime)
            )
          end
        end
      else
        assert(vim.uv.fs_symlink(package .. "/" .. entry, target .. "/" .. entry))
      end
    end
  end
  local function run(mode)
    local init = root .. "/" .. mode .. ".lua"
    local result = root .. "/" .. mode .. ".result"
    write(init, {
      "vim.opt.runtimepath = { " .. vim.inspect(repo) .. ", vim.env.VIMRUNTIME }",
      "vim.opt.packpath = { " .. vim.inspect(root) .. " }",
      "local root, result, mode = "
        .. vim.inspect(root)
        .. ", "
        .. vim.inspect(result)
        .. ", "
        .. vim.inspect(mode),
      [[
      local failure = mode:find('failure', 1, true) ~= nil
      local nodes, units = {}, {}
      for _, name in ipairs({ 'early', 'late', 'ft', 'default', 'native_default', 'bad', 'independent', 'event' }) do
        nodes[name] = {
          name = name,
          after_path = name ~= 'default' and name ~= 'native_default'
            and (root .. '/packages/' .. name .. '/after') or nil,
          after = function()
            assert(vim.g[name .. '_plugin'])
            if name ~= 'default' and name ~= 'native_default' then
              assert(vim.g[name .. '_after'] == 1, 'after/plugin must run before config')
            else
              assert(not vim.g[name .. '_after'], 'default config keeps native timing')
            end
            vim.g[name .. '_config'] = (vim.g[name .. '_config'] or 0) + 1
          end,
        }
        units[#units + 1] = { id = name, members = { name }, dependencies = {} }
      end
      nodes.ft.triggers = { filetypes = { 'divinefixture' } }
      nodes.event.triggers = { events = { 'ColorScheme' } }
      local colors = {}
      vim.api.nvim_create_autocmd('ColorScheme', { pattern = 'divine_*', callback = function(args)
        local name = args.match:sub(#'divine_' + 1)
        colors[name] = (colors[name] or 0) + 1

        -- Reentry from an emitted event must not repeat the source or config.
        if controller then controller.load(name) end
      end })
      vim.filetype.add({ extension = { divinefixture = 'divinefixture' } })
      local startup = failure and {} or { 'early', 'native_default' }
      _G.controller = require('divine').setup({ nodes = nodes, units = units, startup_units = startup })
      if failure then
        local loaded, message = pcall(controller.load, 'bad')
        assert(not loaded and message:find('startup after fixture failed', 1, true))
        assert(not vim.g.bad_config)
        controller.load('independent')
      end
      vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
        vim.schedule(function()
          local success, message = xpcall(function()
            if failure then
              assert(controller.states.bad == 'failed')
              assert(controller.errors.bad:find('startup after fixture failed', 1, true))
              assert(not pcall(controller.load, 'bad'))
              assert(vim.g.bad_after == 1 and vim.g.independent_after == 1)
              assert(controller.states.independent == 'loaded')
            else
              for _, name in ipairs({ 'early', 'late', 'ft' }) do
                assert(vim.g[name .. '_config'] == 1 and vim.g[name .. '_after'] == 1, name)
                assert(colors[name] == 1, name .. ' ColorScheme must fire exactly once')
                controller.load(name)
                assert(vim.g[name .. '_after'] == 1, name .. ' repeated')
              end
              assert(vim.g.default_config and not vim.g.default_after)
              assert((vim.g.native_default_after or 0) == (mode == 'native' and 1 or 0))
              assert(controller.states.event == 'loaded', 'ColorScheme must activate its lazy target')
              assert(vim.g.event_config == 1 and vim.g.event_after == 1)
            end
          end, debug.traceback)
          vim.fn.writefile({ success and 'ok' or tostring(message) }, result)
          vim.cmd(success and 'qa!' or 'cquit 1')
        end)
      end })
      ]],
    })
    local command = { vim.v.progpath, "--headless", "-n", "-i", "NONE", "-u", init }
    if mode ~= "native" and mode ~= "failure_native" then command[#command + 1] = "--noplugin" end
    if not mode:find("failure", 1, true) then
      vim.list_extend(command, {
        root .. "/initial.divinefixture",
        "-c",
        "lua assert(vim.v.vim_did_enter == 0); controller.load('late'); "
          .. "controller.load('default'); assert(vim.g.late_after == 1)",
      })
    end
    local output = vim
      .system(command, { text = true, env = { NVIM = false, NVIM_LOG_FILE = root .. "/nvim.log" } })
      :wait(15000)
    local reported = vim.fn.filereadable(result) == 1 and vim.fn.readfile(result) or {}
    assert(output.code == 0, mode .. ": " .. output.stderr .. table.concat(reported, "\n"))
    assert(#reported > 0, mode .. " did not reach VimEnter")
    assert(reported[1] == "ok", table.concat(reported, "\n"))
  end
  run("native")
  run("disabled")
  run("failure")
  run("failure_native")
end, debug.traceback)
vim.fn.delete(root, "rf")
if not ok then error(err, 0) end
print(
  "after startup: native, late command, initial FileType, noloadplugins, nested events and isolated failure passed"
)
