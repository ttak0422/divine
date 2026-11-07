local T = require("mini.test").new_set()
local mocked, case = require("tests.helpers").new_child_set("plan")
T["isolated plan"] = mocked

mocked["prepares SCC members before configuration and loads shared dependencies once"] = case(
  function(f)
    local controller
    controller = f.runtime.setup({
      nodes = {
        a = {
          name = "a",
          before = function()
            assert(f.prepared.a and f.prepared.b)
            controller.load("b")
            f.record("before:a")
          end,
          after = function() f.record("after:a") end,
        },
        b = { name = "b", before = function() f.record("before:b") end },
        dep = { name = "dep" },
        root = { name = "root" },
      },
      units = {
        { id = "cycle", members = { "a", "b" }, dependencies = { "dep" } },
        { id = "root", members = { "root" }, dependencies = { "dep", "cycle" } },
        { id = "dep", members = { "dep" }, dependencies = {} },
      },
      startup = function() f.record("startup") end,
    })
    f.equal("register,startup,activate")
    f.trace = {}
    controller.load("root")
    f.equal(
      "prepare:dep,cleanup:dep,load:dep,prepare:a,prepare:b,cleanup:a,cleanup:b,"
        .. "before:a,before:b,load:a,load:b,after:a,prepare:root,cleanup:root,load:root"
    )
    f.trace = {}
    controller.load("a")
    controller.load("root")
    f.equal("")
    assert(controller.states.cycle == "loaded")
    assert(not pcall(controller.load, "unknown"))
  end
)

mocked["loads explicit startup units before activating triggers"] = case(function(f)
  f.trace = {}
  local startup = f.singleton("early")
  startup.startup_units = { "early" }
  f.runtime.setup(startup)
  f.equal("register,prepare:early,cleanup:early,load:early,activate")
end)

mocked["uses the custom load hook between before and after"] = case(function(f)
  f.trace = {}
  local replacement = f.singleton(
    "custom",
    function() f.record("before:custom") end,
    function() f.record("after:custom") end
  )
  replacement.nodes.custom.load = function(name) f.record("custom-load:" .. name) end
  f.runtime.setup(replacement).load("custom")
  f.equal(
    "register,activate,prepare:custom,cleanup:custom,before:custom,custom-load:custom,after:custom"
  )
end)

mocked["retains prerequisite and dependent failures"] = case(function(f)
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
  local blocked = f.runtime.setup(dependent)
  assert(not pcall(blocked.load, "dependent"))
  assert(blocked.states.dependent == "failed" and blocked.states.prerequisite == "failed")
  assert(not pcall(blocked.load, "dependent"))
end)

mocked["rejects reentry before runtime preparation"] = case(function(f)
  local reentry
  local recursive = f.singleton("recursive")
  reentry = f.runtime.setup(recursive)
  vim.cmd.packadd = function() reentry.load("recursive") end
  assert(not pcall(reentry.load, "recursive"))
  assert(reentry.errors.recursive:find("reentry before runtime preparation", 1, true))
end)

mocked["retains before failures without automatic retry"] = case(function(f)
  local count = 0
  local failing = f.singleton("failure")
  local function fail()
    count = count + 1
    error("fixture before failed")
  end
  failing.nodes.failure.before = fail
  local failed = f.runtime.setup(failing)
  local success, message = pcall(failed.load, "failure")
  assert(not success and message:find("fixture before failed", 1, true))
  assert(failed.states.failure == "failed")
  assert(not pcall(failed.load, "failure") and count == 1)
end)

mocked["retains load failures without automatic retry"] = case(function(f)
  local count = 0
  local failing = f.singleton("failure")
  local function fail()
    count = count + 1
    error("fixture load failed")
  end
  failing.nodes.failure.load = fail
  local failed = f.runtime.setup(failing)
  local success, message = pcall(failed.load, "failure")
  assert(not success and message:find("fixture load failed", 1, true))
  assert(failed.states.failure == "failed")
  assert(not pcall(failed.load, "failure") and count == 1)
end)

mocked["retains after failures without automatic retry"] = case(function(f)
  local count = 0
  local failing = f.singleton("failure")
  local function fail()
    count = count + 1
    error("fixture after failed")
  end
  failing.nodes.failure.after = fail
  local failed = f.runtime.setup(failing)
  local success, message = pcall(failed.load, "failure")
  assert(not success and message:find("fixture after failed", 1, true))
  assert(failed.states.failure == "failed")
  assert(not pcall(failed.load, "failure") and count == 1)
end)

mocked["retains packadd failures without automatic retry"] = case(function(f)
  local count = 0
  local failing = f.singleton("failure")
  local function fail()
    count = count + 1
    error("fixture packadd failed")
  end
  vim.cmd.packadd = fail
  local failed = f.runtime.setup(failing)
  local success, message = pcall(failed.load, "failure")
  assert(not success and message:find("fixture packadd failed", 1, true))
  assert(failed.states.failure == "failed")
  assert(not pcall(failed.load, "failure") and count == 1)
end)

mocked["rejects cycles between units before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.units[1].dependencies = { "invalid" }
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects unknown unit dependencies before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.units[1].dependencies = { "missing" }
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects a non-function load hook before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.nodes.invalid.load = true
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects unsafe package names before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.nodes.invalid.name = "../unsafe"
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects boolean startup units before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.startup_units = false
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects string startup units before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.startup_units = "invalid"
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects attribute-set startup units before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.startup_units = { unknown = "invalid" }
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects sparse startup units before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.startup_units = { [2] = "invalid" }
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

mocked["rejects unknown startup units before registering triggers"] = case(function(f)
  local invalid = f.singleton("invalid")
  invalid.startup_units = { "missing" }
  assert(not pcall(f.runtime.setup, invalid))
  f.equal("")
end)

-- The real opt-tree case uses a fresh child with no command or trigger stubs.
local native, native_case = require("tests.helpers").new_child_set("native")
T["native opt tree"] = native
native["prepares peer modules before SCC callbacks without sourcing after-plugin"] = native_case(
  function(f)
    for _, name in ipairs({ "divine-fixture-a", "divine-fixture-b" }) do
      f.write(name, "plugin/main.lua", {
        "vim.g.divine_fixture_loads = (vim.g.divine_fixture_loads or 0) + 1",
      })
      f.write(name, "after/plugin/main.lua", { "vim.g.divine_fixture_after = true" })
    end
    f.write("divine-fixture-b", "lua/divine_fixture_peer.lua", { "return { ready = true }" })
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
    local controller = require("divine").setup(plan)
    controller.load("b")
    assert(vim.g.divine_fixture_loads == 2)
    assert(vim.g.divine_fixture_after == nil, "after/plugin must not be manually sourced")
  end
)

return T
