local function check()
  assert(vim.g.divine_startup and vim.g.divine_pre and vim.g.divine_config)
  assert(vim.g.divine_a == 1 and vim.g.divine_b == 1, "startup scripts must run once")
  assert(
    vim.g.divine_native_scans == 2,
    "unguarded scripts follow ordinary native startup scanning"
  )
  assert(vim.g.divine_a_after == 1, "native startup phase must source after/plugin once")
  assert(not vim.g.divine_deferred and not vim.g.divine_deferred_after)
  vim.cmd("DivineFixture! first second")
  assert(vim.g.divine_command_args == "first second" and vim.g.divine_command_bang)
  assert(vim.g.divine_deferred == 1)
  assert(not vim.g.divine_deferred_after, "deferred loading must not source after/plugin")
  assert(require("divine_fixture_deferred").value == "deferred")
  vim.cmd("DivineFixture again")
  assert(vim.g.divine_deferred == 1)
  assert(vim.fn.system({ "divine-fixture-tool" }) == "divine-tool-ok")
  assert(vim.v.shell_error == 0)
  print("generated bundle startup, SCC, command, module, after/plugin and tool checks passed")
end
local ok, err = xpcall(check, debug.traceback)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
