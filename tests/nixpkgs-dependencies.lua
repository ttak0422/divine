local function check()
  local mode = vim.env.DIVINE_DEPENDENCY_MODE
  local function dependency_files()
    return vim.api.nvim_get_runtime_file("autoload/textobj/user.vim", true)
  end
  if mode == "reference" then
    assert(#dependency_files() == 2, "nixpkgs reference exposes both dependency outputs")
  elseif mode == "implicit" then
    assert(#dependency_files() == 0, "metadata-only dependencies must not enter runtimepath")
    assert(not vim.g.loaded_textobj_entire and not vim.g.loaded_textobj_line)
    assert(vim.fn.exists("*textobj#user#plugin") == 0)
  else
    assert(mode == "explicit")
    local files = dependency_files()
    assert(#files == 1, "only the explicitly selected dependency may enter runtimepath")
    assert(vim.fn.resolve(files[1]) == vim.env.DIVINE_SELECTED_USER .. "/autoload/textobj/user.vim")
    assert(vim.g.loaded_textobj_entire == 1 and not vim.g.loaded_textobj_line)
    assert(vim.g.divine_dependency_configs == 1)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "second", "third" })
    vim.cmd("normal yae")
    assert(
      vim.fn.getreg('"') == "first\nsecond\nthird\n",
      "real entire-buffer text object must work"
    )
    vim.api.nvim_exec_autocmds("User", { pattern = "DivineTextobjLine" })
    assert(vim.g.loaded_textobj_line == 1)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd("normal yal")
    assert(vim.fn.getreg('"') == "second", "real deferred line text object must work")
    vim.api.nvim_exec_autocmds("User", { pattern = "DivineTextobjLine" })
    assert(#dependency_files() == 1 and vim.g.divine_dependency_configs == 1)
    assert(vim.fn.system({ "divine-dependency-tool" }) == "dependency-tool-ok")
    assert(vim.v.shell_error == 0)
  end
  assert(vim.v.errmsg == "", "plugin loading must not hide errors: " .. vim.v.errmsg)
  print("nixpkgs dependency " .. mode .. " checks passed")
end
local ok, err = xpcall(check, debug.traceback)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
