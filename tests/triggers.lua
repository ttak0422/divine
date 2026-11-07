package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local triggers = require("divine.triggers")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.opt.packpath:prepend(root)
local function write(name, relative, lines)
  local path = root .. "/pack/divine/opt/" .. name .. "/" .. relative
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end
local function setup(name, conditions)
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
  cleanup, activate = triggers.register(controller, { [name] = { triggers = conditions } })
  if conditions.keys then activate() end
  return function() return count end, activate, cleanup
end
local ok, err = pcall(function()
  local cleanup, activate = triggers.register({ load = function() error("unexpected") end }, {})
  cleanup("missing")
  activate()
  for _, invalid in ipairs({
    { events = { "NotAnEvent" } },
    { commands = { "lowercase" } },
    { keys = { { lhs = "", mode = "n" } } },
    { mystery = {} },
  }) do
    assert(
      not pcall(triggers.register, { load = function() end }, { invalid = { triggers = invalid } })
    )
  end
  vim.api.nvim_create_user_command("DivineConflict", function() end, {})
  assert(
    not pcall(
      triggers.register,
      { load = function() end },
      { conflict = { triggers = { commands = { "DivineConflict" } } } }
    )
  )
  assert(vim.fn.exists(":DivineConflict") == 2)
  vim.keymap.set("n", "<F19>", "<Nop>")
  local _, conflicting_keys = triggers.register({ load = function() end }, {
    conflict = { triggers = { keys = { { lhs = "<F19>" } } } },
  })
  assert(not pcall(conflicting_keys))
  assert(vim.fn.maparg("<F19>", "n") == "<Nop>")

  local saved_leader = vim.g.mapleader
  vim.g.mapleader = " "
  local _, conflict_batch = triggers.register({ load = function() end }, {
    first = { triggers = { keys = { { lhs = "<leader>duplicate" } } } },
    second = { triggers = { keys = { { lhs = " duplicate" } } } },
  })
  assert(not pcall(conflict_batch))
  assert(vim.fn.maparg(" duplicate", "n") == "")
  local clear_early, activate_early = triggers.register({ load = function() end }, {
    early = { triggers = { keys = { { lhs = "<leader>early" } } } },
  })
  clear_early("early")
  activate_early()
  activate_early()
  assert(vim.fn.maparg(" early", "n") == "")
  vim.g.mapleader = saved_leader

  write("command", "plugin/command.lua", {
    'vim.api.nvim_create_user_command("DivineFixture", function(a) _G.divine_command = a '
      .. 'end, { nargs = "*", bang = true, range = true, complete = function() return { '
      .. '"alpha", "beta" } end })',
  })
  local count = setup("command", { commands = { "DivineFixture" } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
  vim.cmd("silent 1,2DivineFixture! hello world")
  assert(
    count() == 1
      and _G.divine_command.bang
      and _G.divine_command.line1 == 1
      and _G.divine_command.line2 == 2
  )
  assert(_G.divine_command.smods.silent and _G.divine_command.args == "hello world")
  vim.cmd("DivineFixture again")
  assert(count() == 1 and _G.divine_command.args == "again")

  write("commandcount", "plugin/count.lua", {
    'vim.api.nvim_create_user_command("DivineCount", function(a) _G.divine_count = a.count end, { count = 0 })',
  })
  count = setup("commandcount", { commands = { "DivineCount" } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one line" })
  vim.cmd("10DivineCount")
  assert(count() == 1 and _G.divine_count == 10)

  write("raw", "plugin/raw.lua", {
    'vim.api.nvim_create_user_command("DivineRaw", function(a) _G.divine_raw = a end, { nargs = "*" })',
  })
  count = setup("raw", { commands = { "DivineRaw" } })
  local raw = [[one  two\ three "four"]]
  vim.cmd("DivineRaw " .. raw)
  assert(_G.divine_raw.args == raw and count() == 1)
  local first_args = _G.divine_raw.fargs
  vim.cmd("DivineRaw " .. raw)
  assert(vim.deep_equal(first_args, _G.divine_raw.fargs))

  write("replacement", "plugin/replacement.lua", {})
  local _, _, remove =
    setup("replacement", { commands = { "DivineReplace" }, keys = { { lhs = "<F17>" } } })
  vim.api.nvim_create_user_command("DivineReplace", function() _G.divine_replacement = true end, {})
  vim.keymap.set("n", "<F17>", "<Nop>")
  remove("replacement")
  vim.cmd("DivineReplace")
  assert(_G.divine_replacement and vim.fn.maparg("<F17>", "n") == "<Nop>")

  write("complete", "plugin/complete.lua", {
    'vim.api.nvim_create_user_command("DivineComplete", function() end, { nargs = "*", '
      .. 'complete = function() return { "alpha", "beta" } end })',
  })
  count = setup("complete", { commands = { "DivineComplete" } })
  assert(vim.deep_equal(vim.fn.getcompletion("DivineComplete ", "cmdline"), { "alpha", "beta" }))
  assert(count() == 1)

  _G.divine_old_event, _G.divine_new_event = 0, 0
  local group = vim.api.nvim_create_augroup("DivineSharedFixture", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "DivineEvent",
    callback = function() _G.divine_old_event = _G.divine_old_event + 1 end,
  })
  write("event", "plugin/event.lua", {
    'vim.api.nvim_create_autocmd("User", { group = "DivineSharedFixture", pattern = '
      .. '"DivineEvent", callback = function(a) _G.divine_new_event = _G.divine_new_event + 1; '
      .. "_G.divine_event_data = a.data end })",
  })
  count = setup("event", { events = { "User" } })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineEvent", data = { first = true } })
  assert(count() == 1 and _G.divine_old_event == 1 and _G.divine_new_event == 1)
  assert(_G.divine_event_data.first)
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineEvent" })
  assert(count() == 1 and _G.divine_old_event == 2 and _G.divine_new_event == 2)

  local other = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(other, root .. "/other-buffer")
  vim.g.divine_other_buffer = other
  write("buffer_event", "plugin/event.lua", {
    'vim.api.nvim_create_autocmd("BufEnter", { pattern = "*", callback = function(a) _G.divine_other_event = a end })',
    'vim.api.nvim_create_autocmd("BufEnter", { buffer = vim.g.divine_other_buffer, '
      .. "callback = function(a) _G.divine_buffer_event = a end })",
  })
  local original_buffer = vim.api.nvim_get_current_buf()
  count = setup("buffer_event", { events = { "BufEnter" } })
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = other, data = { original = true } })
  assert(
    count() == 1 and _G.divine_other_event.buf == other and _G.divine_buffer_event.buf == other
  )
  assert(
    _G.divine_other_event.file == vim.api.nvim_buf_get_name(other)
      and _G.divine_buffer_event.data.original
  )
  assert(vim.api.nvim_get_current_buf() == original_buffer)

  _G.divine_once = 0
  write("once", "plugin/once.lua", {
    'vim.api.nvim_create_autocmd("User", { pattern = "DivineOnce", once = true, callback '
      .. "= function() _G.divine_once = _G.divine_once + 1 end })",
  })
  count = setup("once", { events = { "User" } })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineOnce" })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineOnce" })
  assert(count() == 1 and _G.divine_once == 1)

  vim.cmd("filetype plugin on")
  write("filetype", "ftplugin/divineft.lua", { "vim.g.divine_ft = (vim.g.divine_ft or 0) + 1" })
  write(
    "filetype",
    "after/ftplugin/divineft.lua",
    { "vim.g.divine_after_ft = (vim.g.divine_after_ft or 0) + 1" }
  )
  write("filetype", "after/plugin/never.lua", { 'error("must not source after/plugin")' })
  count = setup("filetype", { filetypes = { "divineft" } })
  vim.bo.filetype = "divineft"
  assert(count() == 1 and vim.g.divine_ft == 1 and vim.g.divine_after_ft == 1)
  vim.cmd.enew()
  vim.bo.filetype = "divineft"
  assert(count() == 1 and vim.g.divine_ft == 2 and vim.g.divine_after_ft == 2)

  vim.cmd("filetype plugin off")
  write(
    "lateft",
    "ftplugin/divinelate.lua",
    { "vim.g.divine_late_ft = (vim.g.divine_late_ft or 0) + 1" }
  )
  write(
    "lateft",
    "after/ftplugin/divinelate.lua",
    { "vim.g.divine_late_after = (vim.g.divine_late_after or 0) + 1" }
  )
  count = setup("lateft", { filetypes = { "divinelate" } })
  vim.cmd("filetype plugin on")
  vim.bo.filetype = "divinelate"
  assert(count() == 1 and vim.g.divine_late_ft == 1 and vim.g.divine_late_after == 1)

  write(
    "currentft",
    "ftplugin/divinecurrent.lua",
    { "vim.g.divine_current_ft = (vim.g.divine_current_ft or 0) + 1" }
  )
  vim.bo.filetype = "divinecurrent"
  count, activate = setup("currentft", { filetypes = { "divinecurrent" } })
  assert(count() == 0)
  activate()
  assert(count() == 1 and vim.g.divine_current_ft == 1)

  write(
    "multift",
    "ftplugin/divinemulti.lua",
    { "vim.b.divine_multi = (vim.b.divine_multi or 0) + 1" }
  )
  write(
    "multift",
    "after/ftplugin/divinemulti.lua",
    { "vim.b.divine_multi_after = (vim.b.divine_multi_after or 0) + 1" }
  )
  write("multift", "plugin/events.lua", {
    'vim.api.nvim_create_autocmd("FileType", { pattern = "divinemulti", callback = function(args)',
    "  vim.b[args.buf].divine_multi_event = (vim.b[args.buf].divine_multi_event or 0) + 1",
    "end })",
  })
  local buffers = { vim.api.nvim_create_buf(false, true), vim.api.nvim_create_buf(false, true) }
  for _, buffer in ipairs(buffers) do
    vim.bo[buffer].filetype = "divinemulti"
  end
  count, activate = setup("multift", { filetypes = { "divinemulti" } })
  activate()
  activate()
  assert(count() == 1)
  for _, buffer in ipairs(buffers) do
    assert(vim.b[buffer].divine_multi == 1 and vim.b[buffer].divine_multi_after == 1)
    assert(vim.b[buffer].divine_multi_event == 1)
  end

  write("key", "plugin/key.lua", {
    'vim.keymap.set("n", "<F18>", function() _G.divine_key = { count = vim.v.count, register = vim.v.register } end)',
  })
  count = setup("key", { keys = { { lhs = "<F18>", mode = "n" } } })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('"a3<F18>', true, false, true), "xt", false)
  assert(count() == 1 and _G.divine_key.count == 3 and _G.divine_key.register == "a")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F18>", true, false, true), "xt", false)
  assert(count() == 1)

  write("insertkey", "plugin/key.lua", { 'vim.keymap.set("i", "<F16>", "inserted")' })
  count = setup("insertkey", { keys = { { lhs = "<F16>", mode = "i" } } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("i<F16><Esc>", true, false, true),
    "xt",
    false
  )
  assert(count() == 1 and vim.api.nvim_get_current_line() == "inserted")

  write("visualkey", "plugin/key.lua", { 'vim.keymap.set("x", "<F15>", "U")' })
  count = setup("visualkey", { keys = { { lhs = "<F15>", mode = "x" } } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "word" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("viw<F15>", true, false, true), "xt", false)
  assert(count() == 1 and vim.api.nvim_get_current_line() == "WORD")

  write("operatorkey", "plugin/key.lua", { 'vim.keymap.set("o", "<F14>", "iw")' })
  count = setup("operatorkey", { keys = { { lhs = "<F14>", mode = "o" } } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "word remains" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("d<F14>", true, false, true), "xt", false)
  assert(count() == 1 and vim.api.nvim_get_current_line() == " remains")

  write(
    "leaderkey",
    "plugin/key.lua",
    { 'vim.keymap.set("n", "<leader>dv", function() _G.divine_leader = true end)' }
  )
  local old_leader = vim.g.mapleader
  vim.g.mapleader = nil
  local controller = require("divine").setup({
    nodes = { leaderkey = { name = "leaderkey", triggers = { keys = { { lhs = "<leader>dv" } } } } },
    units = { { id = "leaderkey", members = { "leaderkey" }, dependencies = {} } },
    startup = function() vim.g.mapleader = " " end,
  })
  vim.api.nvim_feedkeys(" dv", "xt", false)
  assert(_G.divine_leader and controller.states.leaderkey == "loaded")
  vim.g.mapleader = old_leader

  write("module", "lua/divine_fixture/init.lua", { "return { answer = 42 }" })
  write("module", "lua/divine_fixture/child.lua", { "return { child = true }" })
  count = setup("module", { modules = { "divine_fixture" } })
  assert(not pcall(require, "divine_fixture_not_matching"))
  assert(count() == 0)
  assert(require("divine_fixture.child").child and require("divine_fixture").answer == 42)
  assert(count() == 1)
  write("reentry", "lua/divine_reentry.lua", { "return { ready = true }" })
  write("reentry", "plugin/reentry.lua", { '_G.divine_reentry = require("divine_reentry")' })
  count = setup("reentry", { modules = { "divine_reentry" } })
  assert(require("divine_reentry").ready and _G.divine_reentry.ready and count() == 1)
end)
vim.fn.delete(root, "rf")
assert(ok, err)
print("native lazy trigger fixtures passed")
