assert(vim.fn.exists(":Telescope") == 2, "Telescope command is missing")
assert(vim.fn.exists(":ProjectRoot") == 2, "ProjectRoot command is missing")
assert(vim.g.mapleader == " ", "example leader is missing")
assert(vim.fn.executable("rg") == 1, "ripgrep is missing")
assert(vim.fn.executable("fd") == 1, "fd is missing")
assert(vim.fn.executable("sl") == 1, "top-level extraPackages did not provide sl")
local train_version = vim.fn.system({ "sl", "-v" })
assert(vim.v.shell_error == 0, "sl from top-level extraPackages failed")
assert(train_version:find("Version:", 1, true), "sl did not report its version")
assert(
  vim.fn.maparg("<Space>ff", "n"):find("Telescope find_files", 1, true),
  "file picker mapping is missing"
)
assert(require("project_nvim.config").options.manual_mode, "project setup did not run")
assert(
  type(require("telescope").extensions.projects.projects) == "function",
  "projects extension is missing"
)

-- Exercise the directly configured plugin with mapped insert-mode input.
vim.cmd("enew")
local function type_text(text)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  local keys = vim.api.nvim_replace_termcodes("i" .. text .. "<Esc>", true, false, true)
  vim.api.nvim_feedkeys(keys, "xt", false)
  return vim.api.nvim_get_current_line()
end
assert(type_text("(") == "()", "mini.pairs did not insert the closing parenthesis")
assert(type_text("'") == "'", "inline config did not disable apostrophe pairing")
vim.bo.modified = false
require("telescope.builtin").find_files({ cwd = vim.fn.getcwd() })
local prompt = vim.api.nvim_get_current_buf()
assert(require("telescope.actions.state").get_current_picker(prompt), "file picker did not open")
require("telescope.actions").close(prompt)

print(
  "PASS: exported example init, tools including sl, mapping, Telescope, projects and inline mini.pairs behavior"
)
