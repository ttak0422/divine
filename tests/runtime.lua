local T, case = require("tests.helpers").new_child_set("runtime")

T["runs before, packadd and after in order"] = case(function(f)
  f.runtime.load_one("fixture", {
    before = function() f.record("before") end,
    after = function() f.record("after") end,
  })
  f.equal("before,load:fixture,after")
end)

T["stops before loading when before fails"] = case(function(f)
  assert(not pcall(f.runtime.load_one, "fixture", {
    before = function() error("before failed") end,
    load = function() f.record("unexpected load") end,
  }))
  f.equal("")
end)

T["does not run after when loading fails"] = case(function(f)
  assert(not pcall(f.runtime.load_one, "fixture", {
    load = function() error("load failed") end,
    after = function() f.record("unexpected after") end,
  }))
  f.equal("")
end)

T["propagates after failures without undoing the load"] = case(function(f)
  assert(not pcall(f.runtime.load_one, "fixture", {
    load = function() f.record("loaded") end,
    after = function() error("after failed") end,
  }))
  f.equal("loaded")
end)

T["rejects an empty package name"] = case(
  function(f) assert(not pcall(f.runtime.load_one, "", {})) end
)

T["rejects registration without controller and nodes"] = case(
  function() assert(not pcall(require("divine.triggers").register, {})) end
)

return T
