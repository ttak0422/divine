local T, case = require("tests.helpers").new_child_set("native")

T["sources opted-in SCC after scripts after all ordinary plugins and before config"] = case(
  function(f)
    vim.g.trace = {}
    vim.opt.wildignore = "*.vim,*.lua"
    for _, name in ipairs({ "a", "b" }) do
      f.write(name, "plugin/main.lua", { "vim.g['loaded_' .. '" .. name .. "'] = true" })
      f.write(name, "after/plugin/z.vim", { "let g:trace = add(g:trace, '" .. name .. ":vim')" })
      f.write(name, "after/plugin/nested/a.lua", {
        "assert(vim.g.loaded_a and vim.g.loaded_b)",
        "local trace = vim.g.trace; trace[#trace + 1] = '" .. name .. ":lua'; vim.g.trace = trace",
      })
    end
    local controller = require("divine").setup({
      nodes = {
        a = {
          name = "a",
          after_path = f.root .. "/pack/divine/opt/a/after",
          after = function() assert(table.concat(vim.g.trace, ",") == "a:vim,a:lua,b:vim,b:lua") end,
        },
        b = { name = "b", after_path = f.root .. "/pack/divine/opt/b/after" },
      },
      units = { { id = "cycle", members = { "a", "b" }, dependencies = {} } },
    })
    controller.load("a")
    controller.load("b")
    assert(table.concat(vim.g.trace, ",") == "a:vim,a:lua,b:vim,b:lua")
  end
)

T["retains after-plugin failure and skips config without retry"] = case(function(f)
  f.write("failure", "after/plugin/main.lua", {
    "vim.g.attempts = (vim.g.attempts or 0) + 1",
    "error('after fixture failed')",
  })
  local controller = require("divine").setup({
    nodes = {
      failure = {
        name = "failure",
        after_path = f.root .. "/pack/divine/opt/failure/after",
        after = function() vim.g.configured = true end,
      },
    },
    units = { { id = "failure", members = { "failure" }, dependencies = {} } },
  })
  local ok, err = pcall(controller.load, "failure")
  assert(not ok and err:find("after fixture failed", 1, true))
  assert(controller.states.failure == "failed" and not vim.g.configured)
  assert(not pcall(controller.load, "failure") and vim.g.attempts == 1)
end)

T["does not source an after script already loaded through a symlink"] = case(function(f)
  f.write("custom", "after/plugin/space name.lua", { "vim.g.count = (vim.g.count or 0) + 1" })
  local root = f.root .. "/pack/divine/opt/custom"
  assert(vim.uv.fs_symlink(root, f.root .. "/alias"))
  local controller = require("divine").setup({
    nodes = {
      custom = {
        name = "custom",
        after_path = root .. "/after",
        load = function()
          vim.cmd.source(vim.fn.fnameescape(f.root .. "/alias/after/plugin/space name.lua"))
        end,
      },
    },
    units = { { id = "custom", members = { "custom" }, dependencies = {} } },
  })
  controller.load("custom")
  assert(vim.g.count == 1)
end)

T["does not repeat a later sibling sourced by an after script"] = case(function(f)
  local path = f.root .. "/pack/divine/opt/siblings/after"
  f.write("siblings", "after/plugin/a.lua", {
    "vim.cmd.source(" .. vim.inspect(path .. "/plugin/z.lua") .. ")",
  })
  f.write("siblings", "after/plugin/z.lua", { "vim.g.count = (vim.g.count or 0) + 1" })
  require("divine.after").plugins({ path })
  assert(vim.g.count == 1)
end)

T["loads after-ftdetect when detection is already initialized"] = case(function(f)
  vim.cmd("filetype on")
  f.write("detect", "after/ftdetect/example.vim", {
    "let g:detected_scripts = get(g:, 'detected_scripts', 0) + 1",
    "autocmd BufNewFile *.divineexample setfiletype divineexample",
  })
  f.write("detect", "after/ftplugin/divineexample.lua", { "vim.b.after_ftplugin = true" })
  vim.cmd("filetype plugin on")
  local controller = require("divine").setup({
    nodes = { detect = { name = "detect", after_path = f.root .. "/pack/divine/opt/detect/after" } },
    units = { { id = "detect", members = { "detect" }, dependencies = {} } },
  })
  controller.load("detect")
  controller.load("detect")
  vim.cmd.edit(vim.fn.fnameescape(f.root .. "/new.divineexample"))
  assert(vim.bo.filetype == "divineexample" and vim.b.after_ftplugin)
  assert(vim.g.detected_scripts == 1)
  local handlers =
    vim.api.nvim_get_autocmds({ group = "filetypedetect", pattern = "*.divineexample" })
  assert(#handlers == 1)
end)

T["leaves after-ftdetect to later native initialization"] = case(function(f)
  vim.cmd("filetype off")
  f.write(
    "detect",
    "after/ftdetect/example.lua",
    { "vim.g.detected_scripts = (vim.g.detected_scripts or 0) + 1" }
  )
  local controller = require("divine").setup({
    nodes = { detect = { name = "detect", after_path = f.root .. "/pack/divine/opt/detect/after" } },
    units = { { id = "detect", members = { "detect" }, dependencies = {} } },
  })
  controller.load("detect")
  assert(not vim.g.detected_scripts)
  vim.cmd("filetype on")
  assert(vim.g.detected_scripts == 1)
end)

T["loads ftplugin indent and syntax overrides through native FileType replay"] = case(function(f)
  vim.cmd("filetype plugin indent on")
  vim.cmd("syntax on")
  f.write("ft", "plugin/main.lua", { "vim.g.ft_loaded = true" })
  f.write("ft", "after/plugin/main.lua", {
    "assert(vim.g.ft_loaded)",
    "vim.g.ft_after = (vim.g.ft_after or 0) + 1",
  })
  f.write("ft", "ftplugin/divineexample.lua", { "vim.b.ft_value = 'base'" })
  f.write("ft", "after/ftplugin/divineexample.lua", { "vim.b.ft_value = 'after'" })
  f.write("ft", "indent/divineexample.lua", { "vim.bo.shiftwidth = 2" })
  f.write("ft", "after/indent/divineexample.lua", { "vim.bo.shiftwidth = 3" })
  f.write("ft", "syntax/divineexample.lua", { "vim.b.syntax_value = 'base'" })
  f.write("ft", "after/syntax/divineexample.lua", { "vim.b.syntax_value = 'after'" })
  require("divine").setup({
    nodes = {
      ft = {
        name = "ft",
        after_path = f.root .. "/pack/divine/opt/ft/after",
        triggers = { filetypes = { "divineexample" } },
        after = function() assert(vim.g.ft_after == 1) end,
      },
    },
    units = { { id = "ft", members = { "ft" }, dependencies = {} } },
  })
  for _ = 1, 2 do
    vim.cmd.enew()
    vim.bo.filetype = "divineexample"
    assert(vim.b.ft_value == "after" and vim.bo.shiftwidth == 3 and vim.b.syntax_value == "after")
  end
end)

T["keeps additional normal runtime trees before every after directory"] = case(function(f)
  local a, b, old = f.root .. "/a", f.root .. "/b", f.root .. "/old"
  for _, path in ipairs({ a, b, old }) do
    vim.fn.mkdir(path .. "/after", "p")
  end
  vim.opt.runtimepath = { old, old .. "/after" }
  local original = vim.opt.runtimepath:get()
  require("divine.after").add_runtime_paths({})
  assert(vim.deep_equal(vim.opt.runtimepath:get(), original))
  require("divine.after").add_runtime_paths({ a, b, a })
  assert(
    vim.deep_equal(
      vim.opt.runtimepath:get(),
      { old, a, b, old .. "/after", a .. "/after", b .. "/after" }
    )
  )
end)

return T
