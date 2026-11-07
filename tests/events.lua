-- Integration: these are actual compiler outputs, not handwritten runtime plans.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local fixtures = assert(loadfile(assert(arg[1])))()
local triggers = require("divine.triggers")
if arg[2] then
  local native = dofile(arg[2])
  local names = vim.tbl_keys(native.events)
  table.sort(names)
  table.sort(fixtures.names)
  assert(vim.deep_equal(fixtures.names, names), "baseline event catalog drift")
  assert(vim.deep_equal(fixtures.aliases, native.aliases), "baseline alias catalog drift")
end
for _, name in ipairs(fixtures.names) do
  assert(vim.fn.exists("##" .. name) == 1, "runtime lacks baseline event " .. name)
  local id = vim.api.nvim_create_autocmd(name, { command = "" })
  assert(vim.api.nvim_get_autocmds({ id = id })[1].event == name)
  vim.api.nvim_del_autocmd(id)
end
for alias, fixture in pairs(fixtures.plans) do
  for _, fail_first in ipairs({ false, true }) do
    local loaded, replayed = {}, 0
    local nodes, event = fixture.plan.nodes, fixture.canonical
    local ids = vim.tbl_keys(nodes)
    table.sort(ids)
    for _, node in pairs(nodes) do
      assert(vim.deep_equal(node.triggers.events, { event }))
    end
    local original = vim.deepcopy(nodes)
    local group = vim.api.nvim_create_augroup("DivineCompiledEvents", { clear = true })
    local before = #vim.api.nvim_get_autocmds({ event = event })
    triggers.register({
      load = function(id)
        loaded[#loaded + 1] = id
        if fail_first and id == ids[1] then error("compiled event failure") end
        vim.api.nvim_create_autocmd(event, {
          group = group,
          callback = function(args)
            assert(args.event == event and args.data.original)
            replayed = replayed + 1
          end,
        })
      end,
    }, nodes)
    assert(vim.deep_equal(nodes, original))
    assert(#vim.api.nvim_get_autocmds({ event = event }) == before + 1)
    vim.api.nvim_exec_autocmds(alias, { data = { original = true } })
    if fail_first then
      assert(vim.v.errmsg:find("compiled event failure", 1, true))
      assert(vim.deep_equal(loaded, { ids[1] }) and replayed == 0)
      assert(#vim.api.nvim_get_autocmds({ event = event }) == before + 1)
      vim.api.nvim_exec_autocmds(alias:upper(), { data = { original = true } })
    end
    assert(vim.deep_equal(loaded, ids))
    assert(replayed == (fail_first and 2 or 3))
    vim.api.nvim_del_augroup_by_id(group)
    assert(#vim.api.nvim_get_autocmds({ event = event }) == before)
  end
end
print("compiled event catalog, aliases, dispatch, fail-fast and replay passed")
