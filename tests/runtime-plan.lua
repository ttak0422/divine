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

mocked["rejects unknown manual node and unit identifiers without loading"] = case(function(f)
  local controller = f.runtime.setup(f.singleton("known"))
  f.trace = {}
  local ok, err = pcall(controller.load, "unknown")
  assert(not ok and err:find("unknown node: unknown", 1, true))
  ok, err = pcall(controller.load_unit, "unknown")
  assert(not ok and err:find("unknown unit: unknown", 1, true))
  assert(controller.states.known == "unloaded")
  f.equal("")
end)

mocked["supports an empty compiled plan"] = case(function(f)
  local controller = f.runtime.setup({ nodes = {}, units = {}, startup_units = {} })
  assert(vim.tbl_isempty(controller.states) and vim.tbl_isempty(controller.node_units))
  f.equal("register,activate")
end)

mocked["loads ordered package groups with shared hooks and external dependencies first"] = case(
  function(f)
    local plan = {
      nodes = { a = { name = "a" }, b = { name = "b" }, dep = { name = "dep" } },
      configurations = {
        group = {
          members = { "b", "a" },
          before = function()
            assert(f.prepared.a and f.prepared.b)
            f.record("before:group")
          end,
          after = function() f.record("after:group") end,
        },
      },
      units = {
        { id = "dep", members = { "dep" }, dependencies = {} },
        {
          id = "group",
          members = { "b", "a" },
          configurations = { "group" },
          dependencies = { "dep" },
        },
      },
    }
    local controller = f.runtime.setup(plan)
    f.trace = {}
    controller.load("group")
    f.equal(
      "prepare:dep,cleanup:dep,load:dep,prepare:b,prepare:a,cleanup:group,before:group,load:b,load:a,after:group"
    )
    f.trace = {}
    controller.load("group")
    f.equal("")
  end
)

mocked["deduplicates physical loads across independent overlapping configurations"] = case(
  function(f)
    local controller = f.runtime.setup({
      nodes = { a = { name = "a" }, b = { name = "b" }, c = { name = "c" } },
      configurations = {
        first = { members = { "b", "a" }, after = function() f.record("config:first") end },
        second = { members = { "b", "c" }, after = function() f.record("config:second") end },
      },
      units = {
        { id = "first", members = { "b", "a" }, configurations = { "first" }, dependencies = {} },
        { id = "second", members = { "b", "c" }, configurations = { "second" }, dependencies = {} },
      },
    })
    f.trace = {}
    controller.load("first")
    controller.load("second")
    controller.load("first")
    controller.load("second")
    f.equal(
      "prepare:b,prepare:a,cleanup:first,load:b,load:a,config:first,prepare:c,cleanup:second,load:c,config:second"
    )
  end
)

mocked["retains shared package failures across overlapping configurations"] = case(function(f)
  local attempts = 0
  local controller = f.runtime.setup({
    nodes = { a = { name = "a" } },
    configurations = {
      first = {
        members = { "a" },
        load = function()
          attempts = attempts + 1
          error("shared package failed")
        end,
      },
      second = { members = { "a" }, after = function() error("must not configure") end },
    },
    units = {
      { id = "first", members = { "a" }, configurations = { "first" }, dependencies = {} },
      { id = "second", members = { "a" }, configurations = { "second" }, dependencies = {} },
    },
  })
  assert(not pcall(controller.load, "first"))
  local ok, err = pcall(controller.load, "second")
  assert(not ok and err:find("shared package failed", 1, true))
  assert(attempts == 1 and controller.states.second == "failed")
end)

mocked["retains falsey shared failures without retrying overlapping groups"] = case(function(f)
  for _, payload in ipairs({
    { name = "false", raise = function() error(false) end },
    { name = "nil", raise = function() error(nil) end },
  }) do
    local attempts, configured = 0, 0
    local controller = f.runtime.setup({
      nodes = { a = { name = "a" } },
      configurations = {
        first = {
          members = { "a" },
          load = function()
            attempts = attempts + 1
            payload.raise()
          end,
        },
        second = {
          members = { "a" },
          load = function() attempts = attempts + 1 end,
          after = function() configured = configured + 1 end,
        },
      },
      units = {
        { id = "first", members = { "a" }, configurations = { "first" }, dependencies = {} },
        { id = "second", members = { "a" }, configurations = { "second" }, dependencies = {} },
      },
    })
    for _, id in ipairs({ "first", "second", "first", "second" }) do
      local ok, err = pcall(controller.load, id)
      assert(not ok and type(err) == "string" and err:find(payload.name, 1, true))
      assert(controller.states[id] == "failed")
      assert(attempts == 1 and configured == 0)
    end
  end
end)

mocked["keeps singleton configuration separate from package group membership"] = case(function(f)
  local controller = f.runtime.setup({
    nodes = { a = { name = "a", after = function() f.record("config:singleton") end } },
    configurations = {
      group = { members = { "a" }, after = function() f.record("config:group") end },
    },
    units = {
      { id = "a", members = { "a" }, configurations = { "a" }, dependencies = {} },
      { id = "group", members = { "a" }, configurations = { "group" }, dependencies = {} },
    },
  })
  f.trace = {}
  controller.load("group")
  controller.load("a")
  f.equal("prepare:a,cleanup:group,load:a,config:group,cleanup:a,config:singleton")
end)

mocked["rejects cross-group reentry before shared physical loading completes"] = case(function(f)
  local controller
  controller = f.runtime.setup({
    nodes = { a = { name = "a" } },
    configurations = {
      first = {
        members = { "a" },
        load = function()
          local ok, err = pcall(controller.load, "second")
          assert(not ok and err:find("shared package is loading", 1, true))
          error("outer package failed")
        end,
      },
      second = { members = { "a" }, after = function() f.record("wrong-success") end },
    },
    units = {
      { id = "first", members = { "a" }, configurations = { "first" }, dependencies = {} },
      { id = "second", members = { "a" }, configurations = { "second" }, dependencies = {} },
    },
  })
  f.trace = {}
  assert(not pcall(controller.load, "first"))
  assert(controller.states.first == "failed" and controller.states.second == "failed")
  f.equal("prepare:a,cleanup:first")
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

native["hands the first command to an ordered group after shared configuration"] = native_case(
  function(f)
    f.write("group-b", "lua/divine_group_peer.lua", { "return { ready = true }" })
    f.write("group-b", "plugin/main.lua", {
      "vim.g.divine_group_order = (vim.g.divine_group_order or '') .. 'b,'",
      "vim.api.nvim_create_user_command('DivineOrderedGroup', function()",
      "  assert(vim.g.divine_group_config == 1)",
      "  vim.g.divine_group_calls = (vim.g.divine_group_calls or 0) + 1",
      "end, {})",
    })
    f.write("group-a", "plugin/main.lua", {
      "assert(vim.g.divine_group_order == 'b,')",
      "vim.g.divine_group_order = vim.g.divine_group_order .. 'a,'",
    })
    for _, name in ipairs({ "a", "b" }) do
      f.write("group-" .. name, "after/plugin/main.lua", {
        "vim.g.divine_group_order = vim.g.divine_group_order .. 'after-" .. name .. ",'",
      })
    end
    local controller = require("divine").setup({
      nodes = {
        a = { name = "group-a", after_path = f.root .. "/pack/divine/opt/group-a/after" },
        b = { name = "group-b", after_path = f.root .. "/pack/divine/opt/group-b/after" },
      },
      configurations = {
        group = {
          members = { "b", "a" },
          triggers = { commands = { "DivineOrderedGroup" } },
          before = function()
            assert(require("divine_group_peer").ready)
            assert(vim.g.divine_group_order == nil)
            vim.g.divine_group_pre = (vim.g.divine_group_pre or 0) + 1
          end,
          after = function()
            assert(vim.g.divine_group_order == "b,a,after-b,after-a,")
            vim.g.divine_group_config = (vim.g.divine_group_config or 0) + 1
          end,
        },
      },
      units = {
        { id = "group", members = { "b", "a" }, configurations = { "group" }, dependencies = {} },
      },
    })
    vim.cmd.DivineOrderedGroup()
    vim.cmd.DivineOrderedGroup()
    controller.load("group")
    assert(vim.g.divine_group_pre == 1 and vim.g.divine_group_config == 1)
    assert(vim.g.divine_group_calls == 2)
  end
)

return T
