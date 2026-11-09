local MiniTest = require("mini.test")
local M = {}

-- Each case owns a fresh Neovim process and a temporary plugin tree.
-- RPC callbacks must use their fixture argument, not captured Lua upvalues.
function M.new_child_set(kind)
  local child = MiniTest.new_child_neovim()
  local root
  local T = MiniTest.new_set({
    hooks = {
      pre_case = function()
        root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")
        child.restart({ "-u", "NONE", "--noplugin", "-i", "NONE" })
        child.lua([[package.path = "./?.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path]])
        child.g.divine_test_root = root
      end,
      post_case = function()
        local ok, err = pcall(child.stop)
        if root then vim.fn.delete(root, "rf") end
        assert(ok, err)
      end,
    },
  })
  local function case(callback)
    assert(debug.getupvalue(callback, 1) == nil, "child cases must not capture upvalues")
    return function()
      child.lua_func(function(fixture_kind, code)
        assert(package.loaded["mini.test"] == nil, "test framework leaked into the child")
        local fixture = require("tests.fixtures")[fixture_kind]()
        assert(loadstring(code))(fixture)
      end, kind, string.dump(callback))
    end
  end

  -- Expose the driver for input that needs the child main loop between RPC calls.
  return T, case, child
end

return M
