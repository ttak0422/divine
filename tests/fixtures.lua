local M = {}

function M.runtime()
  local f = { trace = {}, prepared = {} }
  function f.record(value) f.trace[#f.trace + 1] = value end
  function f.equal(expected)
    assert(table.concat(f.trace, ",") == expected, table.concat(f.trace, ","))
  end
  vim.cmd = {
    packadd = function(arg)
      if type(arg) == "table" then
        f.prepared[arg[1]] = true
        f.record("prepare:" .. arg[1])
      else
        f.record("load:" .. arg)
      end
    end,
  }
  f.runtime = require("divine")
  function f.singleton(name, before, after)
    return {
      nodes = { [name] = { name = name, before = before, after = after } },
      units = { { id = name, members = { name }, dependencies = {} } },
    }
  end
  return f
end

function M.plan()
  local f = M.runtime()
  package.loaded["divine.triggers"] = {
    register = function()
      f.record("register")
      return function(id) f.record("cleanup:" .. id) end, function() f.record("activate") end
    end,
  }
  return f
end

function M.native()
  local f = { root = vim.g.divine_test_root, triggers = require("divine.triggers") }
  vim.opt.packpath:prepend(f.root)
  function f.write(name, relative, lines)
    local path = f.root .. "/pack/divine/opt/" .. name .. "/" .. relative
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end
  function f.setup(name, conditions)
    local cleanup, activate
    local count = 0
    local controller = {
      load = function(id)
        assert(id == name)
        count = count + 1
        cleanup(id)
        vim.cmd.packadd(name)
      end,
    }
    cleanup, activate = f.triggers.register(controller, { [name] = { triggers = conditions } })
    if conditions.keys then activate() end
    return function() return count end, activate, cleanup
  end
  return f
end

return M
