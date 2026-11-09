-- `-l` makes collection/setup failures nonzero; wait for asynchronous mini.test.
local mini_test = assert(vim.env.MINI_TEST, "MINI_TEST must point to the pinned mini.test package")
vim.opt.runtimepath:prepend(mini_test)
package.path = "./?.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local MiniTest = require("mini.test")
MiniTest.setup()

local manifest = require("tests.cases")
local files = #arg > 0 and arg or vim.tbl_keys(manifest)
table.sort(files)
local cases = {}
for _, file in ipairs(files) do
  local collected = MiniTest.collect({ find_files = function() return { file } end })
  assert(#collected > 0, "empty test suite: " .. file)
  if manifest[file] then
    local names = {}
    for _, item in ipairs(collected) do
      names[#names + 1] = table.concat(item.desc, " / ", 2)
    end
    table.sort(names)
    MiniTest.expect.equality(names, manifest[file])
  end
  vim.list_extend(cases, collected)
end
assert(#cases > 0, "empty test suite: no files")
MiniTest.execute(cases, { reporter = MiniTest.gen_reporter.stdout({ group_depth = 3 }) })

-- The reporter exits with 0/1; a missing completion must not silently pass.
-- This scheduling wait cannot preempt a hung synchronous child RPC.
vim.wait(120000, function() return not MiniTest.is_executing() end, 10)
error("mini.test did not exit through its reporter")
