-- system() exports NVIM as this Neovim's server address to its children.
-- Exercise the complete guard, including its expected nonzero test exits.
local work = vim.fn.tempname()
vim.fn.mkdir(work, "p")
local ok, err = pcall(function()
  local function run(command)
    local output = vim.fn.system(command)
    assert(vim.v.shell_error == 0, output)
    assert(output:find("cleanup guards passed", 1, true), output)
  end
  vim.env.NVIM_BIN = nil
  run({ "env", "-u", "NVIM", "sh", "tests/mini-test-runner.sh" })
  assert(vim.v.servername ~= "", "expected a Neovim server address")
  run({ "sh", "tests/mini-test-runner.sh" })

  local wrapper, marker = work .. "/nvim-wrapper", work .. "/invoked"
  vim.fn.writefile({
    "#!/bin/sh",
    "printf 'called\\n' >> " .. vim.fn.shellescape(marker),
    "exec " .. vim.fn.shellescape(vim.v.progpath) .. ' "$@"',
  }, wrapper)
  vim.fn.setfperm(wrapper, "rwx------")
  vim.env.NVIM_BIN = wrapper
  run({ "sh", "tests/mini-test-runner.sh" })
  assert(#vim.fn.readfile(marker) == 4, "NVIM_BIN must select all four guard invocations")
end)
vim.fn.delete(work, "rf")
if not ok then error(err, 0) end
print("mini.test environment: unset NVIM, Neovim child and NVIM_BIN override passed")
