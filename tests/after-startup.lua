-- Actual startup phases cannot be reproduced by an already-running RPC child.
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local repo = vim.fn.getcwd()
local function write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(vim.split(table.concat(lines, "\n"), "\n", { plain = true }), path)
end
local ok, err = xpcall(function()
  for _, name in ipairs({ "early", "late", "ft", "default", "bad", "independent" }) do
    local package = root .. "/pack/divine/opt/" .. name
    write(package .. "/plugin/main.lua", { "vim.g['" .. name .. "_plugin'] = true" })
    write(package .. "/after/plugin/main.lua", {
      "vim.g['" .. name .. "_after'] = (vim.g['" .. name .. "_after'] or 0) + 1",
      name == "bad" and "error('startup after fixture failed')" or "",
    })
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
      local nodes, units = {}, {}
      for _, name in ipairs({ 'early', 'late', 'ft', 'default', 'bad', 'independent' }) do
        nodes[name] = {
          name = name,
          after_path = name ~= 'default' and (root .. '/pack/divine/opt/' .. name .. '/after') or nil,
          after = function()
            assert(vim.g[name .. '_plugin'])
            assert(not vim.g[name .. '_after'], 'startup config must remain synchronous')
            vim.g[name .. '_config'] = true
          end,
        }
        units[#units + 1] = { id = name, members = { name }, dependencies = {} }
      end
      nodes.ft.triggers = { filetypes = { 'divinefixture' } }
      vim.filetype.add({ extension = { divinefixture = 'divinefixture' } })
      local startup = mode == 'failure' and { 'bad', 'independent' } or { 'early' }
      _G.controller = require('divine').setup({ nodes = nodes, units = units, startup_units = startup })
      vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
        vim.schedule(function()
          local success, message = xpcall(function()
            if mode == 'failure' then
              assert(controller.states.bad == 'failed')
              assert(controller.errors.bad:find('startup after fixture failed', 1, true))
              assert(not pcall(controller.load, 'bad'))
              assert(vim.g.bad_after == 1 and vim.g.independent_after == 1)
              assert(controller.states.independent == 'loaded')
            else
              for _, name in ipairs({ 'early', 'late', 'ft' }) do
                assert(vim.g[name .. '_config'] and vim.g[name .. '_after'] == 1, name)
                controller.load(name)
                assert(vim.g[name .. '_after'] == 1, name .. ' repeated')
              end
              assert(vim.g.default_config and not vim.g.default_after)
            end
          end, debug.traceback)
          vim.fn.writefile({ success and 'ok' or tostring(message) }, result)
          vim.cmd(success and 'qa!' or 'cquit 1')
        end)
      end })
      ]],
    })
    local command = { vim.v.progpath, "--headless", "-n", "-i", "NONE", "-u", init }
    if mode ~= "native" then command[#command + 1] = "--noplugin" end
    if mode ~= "failure" then
      vim.list_extend(command, {
        root .. "/initial.divinefixture",
        "-c",
        "lua assert(vim.v.vim_did_enter == 0); controller.load('late'); "
          .. "controller.load('default'); assert(not vim.g.late_after)",
      })
    end
    local output = vim
      .system(command, { text = true, env = { NVIM = false, NVIM_LOG_FILE = root .. "/nvim.log" } })
      :wait(15000)
    assert(output.code == 0, mode .. ": " .. output.stderr)
    assert(vim.fn.filereadable(result) == 1, mode .. " did not reach VimEnter")
    assert(vim.fn.readfile(result)[1] == "ok", table.concat(vim.fn.readfile(result), "\n"))
  end
  run("native")
  run("disabled")
  run("failure")
end, debug.traceback)
vim.fn.delete(root, "rf")
if not ok then error(err, 0) end
print(
  "after startup: native, late command, initial FileType, noloadplugins and isolated failure passed"
)
