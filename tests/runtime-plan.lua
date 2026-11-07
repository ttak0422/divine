package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local trace = {}
local function record(value) trace[#trace + 1] = value end
local function equal(expected)
  assert(table.concat(trace, ",") == expected, table.concat(trace, ","))
end
local original_triggers = package.loaded["divine.triggers"]
package.loaded["divine.triggers"] = {
  register = function()
    record("register")
    return function(id) record("cleanup:" .. id) end, function() record("activate") end
  end,
}
local runtime = require("divine")
local original_cmd = vim.cmd
local prepared = {}
vim.cmd = {
  packadd = function(arg)
    if type(arg) == "table" then
      prepared[arg[1]] = true
      record("prepare:" .. arg[1])
    else
      record("load:" .. arg)
    end
  end,
}
local function singleton(name, before, after)
  return {
    nodes = { [name] = { name = name, before = before, after = after } },
    units = { { id = name, members = { name }, dependencies = {} } },
  }
end
local ok, err = xpcall(function()
  local controller
  controller = runtime.setup({
    nodes = {
      a = {
        name = "a",
        before = function()
          assert(prepared.a and prepared.b)
          controller.load("b")
          record("before:a")
        end,
        after = function() record("after:a") end,
      },
      b = { name = "b", before = function() record("before:b") end },
      dep = { name = "dep" },
      root = { name = "root" },
    },
    units = {
      { id = "cycle", members = { "a", "b" }, dependencies = { "dep" } },
      { id = "root", members = { "root" }, dependencies = { "dep", "cycle" } },
      { id = "dep", members = { "dep" }, dependencies = {} },
    },
    startup = function() record("startup") end,
  })
  equal("register,startup,activate")
  trace = {}
  controller.load("root")
  equal(
    "prepare:dep,cleanup:dep,load:dep,prepare:a,prepare:b,cleanup:a,cleanup:b,"
      .. "before:a,before:b,load:a,load:b,after:a,prepare:root,cleanup:root,load:root"
  )
  trace = {}
  controller.load("a")
  controller.load("root")
  equal("")
  assert(controller.states.cycle == "loaded")
  assert(not pcall(controller.load, "unknown"))

  trace = {}
  local startup = singleton("early")
  startup.startup_units = { "early" }
  runtime.setup(startup)
  equal("register,prepare:early,cleanup:early,load:early,activate")

  trace = {}
  local replacement = singleton(
    "custom",
    function() record("before:custom") end,
    function() record("after:custom") end
  )
  replacement.nodes.custom.load = function(name) record("custom-load:" .. name) end
  runtime.setup(replacement).load("custom")
  equal(
    "register,activate,prepare:custom,cleanup:custom,before:custom,custom-load:custom,after:custom"
  )

  for _, stage in ipairs({ "before", "load", "after", "packadd" }) do
    local count = 0
    local failing = singleton("failure")
    local function fail()
      count = count + 1
      error("fixture " .. stage .. " failed")
    end
    if stage == "packadd" then
      vim.cmd.packadd = fail
    else
      failing.nodes.failure[stage] = fail
    end
    local failed = runtime.setup(failing)
    local success, message = pcall(failed.load, "failure")
    assert(not success and message:find("fixture " .. stage .. " failed", 1, true))
    assert(failed.states.failure == "failed")
    assert(not pcall(failed.load, "failure") and count == 1)
    vim.cmd.packadd = function() end
  end

  local dependent = {
    nodes = {
      dependent = { name = "dependent" },
      prerequisite = { name = "prerequisite", before = function() error("prerequisite failed") end },
    },
    units = {
      { id = "dependent", members = { "dependent" }, dependencies = { "prerequisite" } },
      { id = "prerequisite", members = { "prerequisite" }, dependencies = {} },
    },
  }
  local blocked = runtime.setup(dependent)
  assert(not pcall(blocked.load, "dependent"))
  assert(blocked.states.dependent == "failed" and blocked.states.prerequisite == "failed")
  assert(not pcall(blocked.load, "dependent"))

  local reentry
  local recursive = singleton("recursive")
  reentry = runtime.setup(recursive)
  vim.cmd.packadd = function() reentry.load("recursive") end
  assert(not pcall(reentry.load, "recursive"))
  assert(reentry.errors.recursive:find("reentry before runtime preparation", 1, true))

  trace = {}
  local invalid = singleton("invalid")
  invalid.units[1].dependencies = { "invalid" }
  assert(not pcall(runtime.setup, invalid))
  equal("") -- No registration before full graph validation.
  invalid.units[1].dependencies = { "missing" }
  assert(not pcall(runtime.setup, invalid))
  invalid.units[1].dependencies = {}
  for _, malformed in ipairs({
    false,
    "invalid",
    { unknown = "invalid" },
    { [2] = "invalid" },
    { "missing" },
  }) do
    invalid.startup_units = malformed
    assert(not pcall(runtime.setup, invalid))
  end
  invalid.startup_units = nil
  invalid.nodes.invalid.load = true
  assert(not pcall(runtime.setup, invalid))
  invalid.nodes.invalid.load = nil
  equal("")
  invalid.nodes.invalid.name = "../unsafe"
  assert(not pcall(runtime.setup, invalid))
end, debug.traceback)
vim.cmd = original_cmd
assert(ok, err)

-- Real opt fixtures: both Lua runtimes exist before either SCC callback runs.
local root = vim.fn.tempname()
local original_packpath = vim.o.packpath
local original_runtimepath = vim.o.runtimepath
local function write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end
for _, name in ipairs({ "divine-fixture-a", "divine-fixture-b" }) do
  local base = root .. "/pack/fixture/opt/" .. name
  write(
    base .. "/plugin/main.lua",
    { "vim.g.divine_fixture_loads = (vim.g.divine_fixture_loads or 0) + 1" }
  )
  write(base .. "/after/plugin/main.lua", { "vim.g.divine_fixture_after = true" })
end
write(
  root .. "/pack/fixture/opt/divine-fixture-b/lua/divine_fixture_peer.lua",
  { "return { ready = true }" }
)
vim.o.packpath = root
ok, err = xpcall(function()
  local plan = {
    nodes = {
      a = {
        name = "divine-fixture-a",
        before = function()
          assert(require("divine_fixture_peer").ready)
          assert(vim.g.divine_fixture_loads == nil)
        end,
        after = function() assert(vim.g.divine_fixture_loads == 2) end,
      },
      b = { name = "divine-fixture-b" },
    },
    units = { { id = "cycle", members = { "a", "b" }, dependencies = {} } },
    startup_units = { "cycle" },
  }
  local controller = runtime.setup(plan)
  controller.load("b")
  assert(vim.g.divine_fixture_loads == 2)
  assert(vim.g.divine_fixture_after == nil, "after/plugin must not be manually sourced")
end, debug.traceback)
vim.o.packpath, vim.o.runtimepath = original_packpath, original_runtimepath
vim.fn.delete(root, "rf")
package.loaded["divine.triggers"] = original_triggers
assert(ok, err)
print(
  "runtime plan fixtures passed: SCC preparation, shared dependencies, startup, reentry and failures"
)
