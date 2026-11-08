assert(vim.fn.exists(":Telescope") == 2, "Telescope command is missing")
assert(vim.fn.exists(":ProjectRoot") == 2, "ProjectRoot command is missing")
assert(vim.g.mapleader == " ", "example leader is missing")
assert(vim.fn.executable("rg") == 1, "ripgrep is missing")
assert(vim.fn.executable("fd") == 1, "fd is missing")
assert(
  vim.fn.maparg("<Space>ff", "n"):find("Telescope find_files", 1, true),
  "file picker mapping is missing"
)
assert(require("project_nvim.config").options.manual_mode, "project setup did not run")
assert(
  type(require("telescope").extensions.projects.projects) == "function",
  "projects extension is missing"
)
require("telescope.builtin").find_files({ cwd = vim.fn.getcwd() })
local prompt = vim.api.nvim_get_current_buf()
assert(require("telescope.actions.state").get_current_picker(prompt), "file picker did not open")
require("telescope.actions").close(prompt)
print("PASS: exported example init, tools, mapping, Telescope picker and project integration")
