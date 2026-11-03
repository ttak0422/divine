package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local original_cmd = vim.cmd
local trace = {}
local function record(value) trace[#trace + 1] = value end
vim.cmd = { packadd = function(name) record("load:" .. name) end }

local ok, err = pcall(function()
  local runtime = require("divine")
  runtime.load_one("fixture", {
    before = function() record("before") end,
    after = function() record("after") end,
  })
  assert(table.concat(trace, ",") == "before,load:fixture,after")

  trace = {}
  assert(not pcall(runtime.load_one, "fixture", {
    before = function() error("before failed") end,
    load = function() record("unexpected load") end,
  }))
  assert(#trace == 0)

  assert(not pcall(runtime.load_one, "fixture", {
    load = function() error("load failed") end,
    after = function() record("unexpected after") end,
  }))
  assert(#trace == 0)
  assert(not pcall(runtime.load_one, "fixture", {
    load = function() record("loaded") end,
    after = function() error("after failed") end,
  }))
  assert(table.concat(trace, ",") == "loaded")
  assert(not pcall(runtime.load_one, "", {}))
  assert(not pcall(require("divine.triggers").register, {}))
end)
vim.cmd = original_cmd
assert(ok, err)
print("runtime fixture checks passed; no plugin or after/plugin scripts sourced")
