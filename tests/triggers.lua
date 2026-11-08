local T, case, child = require("tests.helpers").new_child_set("native")

T["accepts empty trigger declarations"] = case(function(f)
  local cleanup, activate = f.triggers.register({ load = function() error("unexpected") end }, {})
  cleanup("missing")
  activate()
end)

T["rejects unknown events"] = case(function(f)
  local invalid = { events = { "NotAnEvent" } }
  assert(
    not pcall(f.triggers.register, { load = function() end }, { invalid = { triggers = invalid } })
  )
end)

T["rejects lowercase commands"] = case(function(f)
  local invalid = { commands = { "lowercase" } }
  assert(
    not pcall(f.triggers.register, { load = function() end }, { invalid = { triggers = invalid } })
  )
end)

T["rejects empty key sequences"] = case(function(f)
  local invalid = { keys = { { lhs = "", mode = "n" } } }
  assert(
    not pcall(f.triggers.register, { load = function() end }, { invalid = { triggers = invalid } })
  )
end)

T["rejects unknown trigger categories"] = case(function(f)
  local invalid = { mystery = {} }
  assert(
    not pcall(f.triggers.register, { load = function() end }, { invalid = { triggers = invalid } })
  )
end)

T["preserves an existing command on registration conflict"] = case(function(f)
  vim.api.nvim_create_user_command("DivineConflict", function() end, {})
  assert(
    not pcall(
      f.triggers.register,
      { load = function() end },
      { conflict = { triggers = { commands = { "DivineConflict" } } } }
    )
  )
  assert(vim.fn.exists(":DivineConflict") == 2)
end)

T["preserves an existing key on activation conflict"] = case(function(f)
  vim.keymap.set("n", "<F19>", "<Nop>")
  local _, conflicting_keys = f.triggers.register({ load = function() end }, {
    conflict = { triggers = { keys = { { lhs = "<F19>" } } } },
  })
  assert(not pcall(conflicting_keys))
  assert(vim.fn.maparg("<F19>", "n") == "<Nop>")
end)

T["rejects expanded leader conflicts before installing any key"] = case(function(f)
  vim.g.mapleader = " "
  local _, conflict_batch = f.triggers.register({ load = function() end }, {
    first = { triggers = { keys = { { lhs = "<leader>duplicate" } } } },
    second = { triggers = { keys = { { lhs = " duplicate" } } } },
  })
  assert(not pcall(conflict_batch))
  assert(vim.fn.maparg(" duplicate", "n") == "")
end)

T["does not activate keys cleared before activation"] = case(function(f)
  vim.g.mapleader = " "
  local clear_early, activate_early = f.triggers.register({ load = function() end }, {
    early = { triggers = { keys = { { lhs = "<leader>early" } } } },
  })
  clear_early("early")
  activate_early()
  activate_early()
  assert(vim.fn.maparg(" early", "n") == "")
end)

T["hands off command range, bang, modifiers and repeated invocations"] = case(function(f)
  f.write("command", "plugin/command.lua", {
    'vim.api.nvim_create_user_command("DivineFixture", function(a) _G.divine_command = a '
      .. 'end, { nargs = "*", bang = true, range = true, complete = function() return { '
      .. '"alpha", "beta" } end })',
  })
  local count = f.setup("command", { commands = { "DivineFixture" } })
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
end)

T["hands off a command count beyond the current buffer"] = case(function(f)
  f.write("commandcount", "plugin/count.lua", {
    'vim.api.nvim_create_user_command("DivineCount", function(a) _G.divine_count = a.count end, { count = 0 })',
  })
  local count = f.setup("commandcount", { commands = { "DivineCount" } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one line" })
  vim.cmd("10DivineCount")
  assert(count() == 1 and _G.divine_count == 10)
end)

T["preserves raw command arguments and parsed argument parity"] = case(function(f)
  f.write("raw", "plugin/raw.lua", {
    'vim.api.nvim_create_user_command("DivineRaw", function(a) _G.divine_raw = a end, { nargs = "*" })',
  })
  local count = f.setup("raw", { commands = { "DivineRaw" } })
  local raw = [[one  two\ three "four"]]
  vim.cmd("DivineRaw " .. raw)
  assert(_G.divine_raw.args == raw and count() == 1)
  local first_args = _G.divine_raw.fargs
  vim.cmd("DivineRaw " .. raw)
  assert(vim.deep_equal(first_args, _G.divine_raw.fargs))
end)

T["cleanup preserves commands and keys replaced by the user"] = case(function(f)
  f.write("replacement", "plugin/replacement.lua", {})
  local _, _, remove =
    f.setup("replacement", { commands = { "DivineReplace" }, keys = { { lhs = "<F17>" } } })
  vim.api.nvim_create_user_command("DivineReplace", function() _G.divine_replacement = true end, {})
  vim.keymap.set("n", "<F17>", "<Nop>")
  remove("replacement")
  vim.cmd("DivineReplace")
  assert(_G.divine_replacement and vim.fn.maparg("<F17>", "n") == "<Nop>")
end)

T["loads a command on first completion and returns plugin results"] = case(function(f)
  f.write("complete", "plugin/complete.lua", {
    'vim.api.nvim_create_user_command("DivineComplete", function() end, { nargs = "*", '
      .. 'complete = function() return { "alpha", "beta" } end })',
  })
  local count = f.setup("complete", { commands = { "DivineComplete" } })
  assert(vim.deep_equal(vim.fn.getcompletion("DivineComplete ", "cmdline"), { "alpha", "beta" }))
  assert(count() == 1)
end)

T["replays new groups while excluding existing groups and unscoped handlers"] = case(function(f)
  local calls = { old = 0, shared = 0, unscoped = 0, fresh = 0 }
  local shared = vim.api.nvim_create_augroup("DivineShared", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = shared,
    pattern = "DivineEvent",
    callback = function() calls.old = calls.old + 1 end,
  })
  f.triggers.register({
    load = function()
      for _, name in ipairs({ "shared", "unscoped", "fresh" }) do
        local options = {
          pattern = "DivineEvent",
          callback = function(a)
            calls[name] = calls[name] + 1
            if name == "fresh" then assert(a.match == "DivineEvent" and a.data.first) end
          end,
        }
        if name == "shared" then options.group = shared end
        if name == "fresh" then
          options.group = vim.api.nvim_create_augroup("DivineFresh", { clear = true })
        end
        vim.api.nvim_create_autocmd("User", options)
      end
    end,
  }, { event = { triggers = { events = { "User" } } } })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineEvent", data = { first = true } })
  assert(
    vim.deep_equal(calls, { old = 1, shared = 0, unscoped = 0, fresh = 1 }),
    vim.inspect(calls)
  )
end)

T["replays buffer events with original buffer and event data"] = case(function(f)
  local other = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(other, f.root .. "/other-buffer")
  vim.g.divine_other_buffer = other
  f.write("buffer_event", "plugin/event.lua", {
    'local group = vim.api.nvim_create_augroup("DivineBuffer", { clear = true })',
    'vim.api.nvim_create_autocmd("BufEnter", { group = group, pattern = "*", '
      .. "callback = function(a) _G.divine_other_event = a end })",
    'vim.api.nvim_create_autocmd("BufEnter", { group = group, buffer = vim.g.divine_other_buffer, '
      .. "callback = function(a) _G.divine_buffer_event = a end })",
  })
  local original_buffer = vim.api.nvim_get_current_buf()
  local count = f.setup("buffer_event", { events = { "BufEnter" } })
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = other, data = { original = true } })
  assert(
    count() == 1 and _G.divine_other_event.buf == other and _G.divine_buffer_event.buf == other
  )
  assert(
    _G.divine_other_event.file == vim.api.nvim_buf_get_name(other)
      and _G.divine_buffer_event.data.original
  )
  assert(vim.api.nvim_get_current_buf() == original_buffer)
end)

T["executes new once handlers only once"] = case(function(f)
  _G.divine_once = 0
  f.write("once", "plugin/once.lua", {
    'local group = vim.api.nvim_create_augroup("DivineOnceGroup", { clear = true })',
    'vim.api.nvim_create_autocmd("User", { group = group, pattern = "DivineOnce", once = true, callback '
      .. "= function() _G.divine_once = _G.divine_once + 1 end })",
  })
  local count = f.setup("once", { events = { "User" } })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineOnce" })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineOnce" })
  assert(count() == 1 and _G.divine_once == 1)
end)

T["loads ftplugin and after-ftplugin for first and later buffers"] = case(function(f)
  vim.cmd("filetype plugin on")
  f.write("filetype", "ftplugin/divineft.lua", { "vim.g.divine_ft = (vim.g.divine_ft or 0) + 1" })
  f.write(
    "filetype",
    "after/ftplugin/divineft.lua",
    { "vim.g.divine_after_ft = (vim.g.divine_after_ft or 0) + 1" }
  )
  f.write("filetype", "after/plugin/never.lua", { 'error("must not source after/plugin")' })
  local count = f.setup("filetype", { filetypes = { "divineft" } })
  vim.bo.filetype = "divineft"
  assert(count() == 1 and vim.g.divine_ft == 1 and vim.g.divine_after_ft == 1)
  vim.cmd.enew()
  vim.bo.filetype = "divineft"
  assert(count() == 1 and vim.g.divine_ft == 2 and vim.g.divine_after_ft == 2)
end)

T["supports filetype registration before enabling filetype plugins"] = case(function(f)
  vim.cmd("filetype plugin off")
  f.write(
    "lateft",
    "ftplugin/divinelate.lua",
    { "vim.g.divine_late_ft = (vim.g.divine_late_ft or 0) + 1" }
  )
  f.write(
    "lateft",
    "after/ftplugin/divinelate.lua",
    { "vim.g.divine_late_after = (vim.g.divine_late_after or 0) + 1" }
  )
  local count = f.setup("lateft", { filetypes = { "divinelate" } })
  vim.cmd("filetype plugin on")
  vim.bo.filetype = "divinelate"
  -- The original dispatch still has the native loader pending after replay.
  assert(
    count() == 1 and vim.g.divine_late_ft == 2 and vim.g.divine_late_after == 2,
    vim.inspect({ count(), vim.g.divine_late_ft, vim.g.divine_late_after })
  )
end)

T["activates the current filetype after registration"] = case(function(f)
  vim.cmd("filetype plugin on")
  f.write(
    "currentft",
    "ftplugin/divinecurrent.lua",
    { "vim.g.divine_current_ft = (vim.g.divine_current_ft or 0) + 1" }
  )
  vim.bo.filetype = "divinecurrent"
  local count, activate = f.setup("currentft", { filetypes = { "divinecurrent" } })
  assert(count() == 0)
  activate()
  assert(count() == 1 and vim.g.divine_current_ft == 1)
end)

T["activates all matching open buffers only once"] = case(function(f)
  vim.cmd("filetype plugin on")
  f.write(
    "multift",
    "ftplugin/divinemulti.lua",
    { "vim.b.divine_multi = (vim.b.divine_multi or 0) + 1" }
  )
  f.write(
    "multift",
    "after/ftplugin/divinemulti.lua",
    { "vim.b.divine_multi_after = (vim.b.divine_multi_after or 0) + 1" }
  )
  f.write("multift", "plugin/events.lua", {
    'vim.api.nvim_create_autocmd("FileType", { pattern = "divinemulti", callback = function(args)',
    "  vim.b[args.buf].divine_multi_event = (vim.b[args.buf].divine_multi_event or 0) + 1",
    "end })",
  })
  local buffers = { vim.api.nvim_create_buf(false, true), vim.api.nvim_create_buf(false, true) }
  for _, buffer in ipairs(buffers) do
    vim.bo[buffer].filetype = "divinemulti"
  end
  local count, activate = f.setup("multift", { filetypes = { "divinemulti" } })
  activate()
  activate()
  assert(count() == 1)
  for _, buffer in ipairs(buffers) do
    assert(vim.b[buffer].divine_multi == 1 and vim.b[buffer].divine_multi_after == 1)
    assert(vim.b[buffer].divine_multi_event == 1)
  end
end)

T["hands off normal-mode count and register on the first key"] = case(function(f)
  f.write("key", "plugin/key.lua", {
    'vim.keymap.set("n", "<F18>", function() _G.divine_key = { count = vim.v.count, register = vim.v.register } end)',
  })
  local count = f.setup("key", { keys = { { lhs = "<F18>", mode = "n" } } })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('"a3<F18>', true, false, true), "xt", false)
  assert(count() == 1 and _G.divine_key.count == 3 and _G.divine_key.register == "a")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F18>", true, false, true), "xt", false)
  assert(count() == 1)
end)

T["hands off insert-mode keys"] = case(function(f)
  f.write("insertkey", "plugin/key.lua", { 'vim.keymap.set("i", "<F16>", "inserted")' })
  local count = f.setup("insertkey", { keys = { { lhs = "<F16>", mode = "i" } } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("i<F16><Esc>", true, false, true),
    "xt",
    false
  )
  assert(count() == 1 and vim.api.nvim_get_current_line() == "inserted")
end)

T["hands off visual-mode keys"] = case(function(f)
  f.write("visualkey", "plugin/key.lua", { 'vim.keymap.set("x", "<F15>", "U")' })
  local count = f.setup("visualkey", { keys = { { lhs = "<F15>", mode = "x" } } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "word" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("viw<F15>", true, false, true), "xt", false)
  assert(count() == 1 and vim.api.nvim_get_current_line() == "WORD")
end)

T["hands off select-mode character line and block selections"] = case(function(f)
  f.write("selectkey", "plugin/key.lua", {
    'vim.keymap.set("s", "<F13>", function()',
    "  _G.divine_select_context = { mode = vim.fn.mode(1),",
    '    anchor = vim.fn.getpos("v"), cursor = vim.api.nvim_win_get_cursor(0) }',
    '  return "replacement"',
    "end, { expr = true })",
  })
  for _, selection in ipairs({ "viw<C-g>", "V<C-g>", "<C-v>jl<C-g>" }) do
    local function run()
      _G.divine_select_context = nil
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one two", "three four", "five six" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes(selection .. "<F13><Esc>", true, false, true),
        "xt",
        false
      )
      return {
        context = _G.divine_select_context,
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        cursor = vim.api.nvim_win_get_cursor(0),
        mode = vim.fn.mode(1),
      }
    end
    vim.cmd.packadd("selectkey")
    local native = run()
    assert(native.context ~= nil and native.lines[1]:find("replacement", 1, true))
    vim.keymap.del("s", "<F13>")
    local count = f.setup("selectkey", { keys = { { lhs = "<F13>", mode = "s" } } })
    assert(vim.deep_equal(run(), native), "first selection differs: " .. selection)
    assert(vim.deep_equal(run(), native), "loaded selection differs: " .. selection)
    assert(count() == 1)
    vim.keymap.del("s", "<F13>")
  end
end)

T["hands off terminal-mode input on first and repeated keys"] = function()
  case(function(f)
    f.write("terminalkey", "plugin/key.lua", {
      'vim.keymap.set("t", "<F12>", function()',
      "  _G.divine_terminal_context = vim.fn.mode(1)",
      '  return "terminal-input\\r"',
      "end, { expr = true })",
    })
    _G.divine_terminal_setup = function(lazy)
      local buffer = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buffer)
      _G.divine_terminal_input, _G.divine_terminal_context = "", nil
      local channel = vim.api.nvim_open_term(buffer, {
        on_input = function(_, _, _, data)
          _G.divine_terminal_input = _G.divine_terminal_input .. data
        end,
      })
      vim.api.nvim_chan_send(channel, "terminal ready\r\n")
      if lazy then
        _G.divine_terminal_count = f.setup("terminalkey", {
          keys = { { lhs = "<F12>", mode = "t" } },
        })
      else
        vim.cmd.packadd("terminalkey")
      end
    end
  end)()
  -- Terminal input needs the child's main loop, outside a synchronous Lua RPC.
  local function run(lazy)
    child.lua("_G.divine_terminal_setup(...)", { lazy })
    child.type_keys("i")
    assert(child.lua_get("vim.fn.mode(1)") == "t")
    local states = {}
    for invocation = 1, 2 do
      child.type_keys("<F12>")
      assert(
        vim.wait(
          1000,
          function()
            return child.lua_get("_G.divine_terminal_input")
              == string.rep("terminal-input\r", invocation)
          end
        ),
        "terminal input was lost or changed"
      )
      states[invocation] = child.lua_get([[{
        input = _G.divine_terminal_input,
        context = _G.divine_terminal_context,
        mode = vim.fn.mode(1),
      }]])
      assert(states[invocation].context == "t" and states[invocation].mode == "t")
      if lazy then assert(child.lua_get("_G.divine_terminal_count()") == 1) end
    end
    child.type_keys([[<C-\><C-n>]])
    assert(child.lua_get("vim.fn.mode(1)") == "nt")
    child.lua([[vim.keymap.del("t", "<F12>"); vim.api.nvim_buf_delete(0, { force = true })]])
    return states
  end
  local native = run(false)
  assert(vim.deep_equal(run(true), native), "terminal handoff differs from native input")
end

T["hands off operator-pending keys without reconstructing operators"] = case(function(f)
  f.write("operatorkey", "plugin/key.lua", {
    'vim.keymap.set("o", "<F14>", "w")',
  })
  for _, keys in ipairs({ "d<F14>", "g~<F14>", "dV<F14>", '"a2d3<F14>', "2g~3<F14>" }) do
    local function run()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {
        "one two three four five six seven eight",
        "second line",
        "third line",
      })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.fn.setreg('"', "initial")
      vim.fn.setreg("a", "initial")
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
      return {
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        cursor = vim.api.nvim_win_get_cursor(0),
        unnamed = vim.fn.getreg('"'),
        named = vim.fn.getreg("a"),
        register_type = vim.fn.getregtype('"'),
        mode = vim.api.nvim_get_mode().mode,
      }
    end
    vim.keymap.set("o", "<F14>", "w")
    local native = run()
    vim.keymap.del("o", "<F14>")
    local count = f.setup("operatorkey", { keys = { { lhs = "<F14>", mode = "o" } } })
    assert(vim.deep_equal(run(), native), "first operation differs: " .. keys)
    assert(vim.deep_equal(run(), native), "loaded operation differs: " .. keys)
    assert(count() == 1)
    vim.keymap.del("o", "<F14>")
  end
end)

T["preserves operator context for expression mappings and leader keys"] = case(function(f)
  vim.g.mapleader = " "
  f.write("operatorexpr", "plugin/key.lua", {
    'vim.keymap.set("o", "<leader>op", function()',
    "  _G.divine_operator_context = { vim.v.count, vim.v.count1, vim.v.register, vim.v.operator, vim.fn.mode(1) }",
    '  return "iw"',
    "end, { expr = true })",
  })
  _G.divine_operator = function(kind) _G.divine_operator_kind = kind end
  vim.go.operatorfunc = "v:lua.divine_operator"
  for _, keys in ipairs({ '"a2d3 op', "g~ op", "dV op", "c opX<Esc>", "g@ op" }) do
    local function run()
      _G.divine_operator_context, _G.divine_operator_kind = nil, nil
      vim.api.nvim_buf_set_lines(
        0,
        0,
        -1,
        false,
        { "one two three four five six seven", "next line" }
      )
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
      return {
        context = _G.divine_operator_context,
        kind = _G.divine_operator_kind,
        lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
        cursor = vim.api.nvim_win_get_cursor(0),
        mode = vim.fn.mode(1),
      }
    end
    vim.cmd.packadd("operatorexpr")
    local native = run()
    assert(native.context ~= nil)
    vim.keymap.del("o", "<leader>op")
    local count = f.setup("operatorexpr", { keys = { { lhs = "<leader>op", mode = "o" } } })
    assert(vim.deep_equal(run(), native), "first expression context differs: " .. keys)
    assert(vim.deep_equal(run(), native), "loaded expression context differs: " .. keys)
    assert(count() == 1)
    vim.keymap.del("o", "<leader>op")
  end
end)

T["cleans failed operator triggers when configuration violates textlock"] = case(function(f)
  f.write("lockedkey", "plugin/key.lua", { "vim.g.divine_locked_plugin = true" })
  local calls = 0
  local controller = require("divine").setup({
    nodes = {
      lockedkey = {
        name = "lockedkey",
        triggers = { keys = { { lhs = "<F14>", mode = "o" } }, commands = { "DivineLocked" } },
        before = function()
          calls = calls + 1
          vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unexpected edit" })
        end,
      },
    },
    units = { { id = "lockedkey", members = { "lockedkey" }, dependencies = {} } },
  })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one two" })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("d<F14>", true, false, true), "xt", false)
  assert(controller.states.lockedkey == "failed")
  assert(controller.errors.lockedkey:find("E565", 1, true), controller.errors.lockedkey)
  assert(vim.v.errmsg:find("E565", 1, true), vim.v.errmsg)
  assert(vim.api.nvim_get_current_line() == "one two")
  assert(vim.api.nvim_get_mode().mode == "n", vim.inspect(vim.api.nvim_get_mode()))
  assert(vim.fn.maparg("<F14>", "o") == "")
  assert(vim.fn.exists(":DivineLocked") == 0)
  assert(not vim.g.divine_locked_plugin)
  local ok, err = pcall(controller.load, "lockedkey")
  assert(not ok and err == controller.errors.lockedkey and calls == 1)
end)

T["expands leader keys after common startup configuration"] = case(function(f)
  f.write(
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
end)

T["matches exact and dotted modules without prefix collisions"] = case(function(f)
  f.write("module", "lua/divine_fixture/init.lua", { "return { answer = 42 }" })
  f.write("module", "lua/divine_fixture/child.lua", { "return { child = true }" })
  local count = f.setup("module", { modules = { "divine_fixture" } })
  assert(not pcall(require, "divine_fixture_not_matching"))
  assert(count() == 0)
  assert(require("divine_fixture.child").child and require("divine_fixture").answer == 42)
  assert(count() == 1)
end)

T["allows module reentry from the loaded plugin script"] = case(function(f)
  f.write("reentry", "lua/divine_reentry.lua", { "return { ready = true }" })
  f.write("reentry", "plugin/reentry.lua", { '_G.divine_reentry = require("divine_reentry")' })
  local count = f.setup("reentry", { modules = { "divine_reentry" } })
  assert(require("divine_reentry").ready and _G.divine_reentry.ready and count() == 1)
end)

T["preserves native once semantics for multiple patterns"] = case(function(f)
  local calls = {}
  f.triggers.register({
    load = function()
      vim.api.nvim_create_autocmd("User", {
        group = vim.api.nvim_create_augroup("DivinePatternOnce", { clear = true }),
        pattern = { "DivineFirst", "DivineSecond" },
        once = true,
        callback = function(a) calls[#calls + 1] = a.match end,
      })
    end,
  }, { event = { triggers = { events = { "User" } } } })
  for _, pattern in ipairs({ "DivineFirst", "DivineFirst", "DivineSecond", "DivineSecond" }) do
    vim.api.nvim_exec_autocmds("User", { pattern = pattern })
  end
  assert(vim.deep_equal(calls, { "DivineFirst", "DivineSecond" }), vim.inspect(calls))
end)

T["preserves Ex once and script-local handlers"] = case(function(f)
  f.write("script", "plugin/events.vim", {
    "let s:count = 0",
    "function! s:Record() abort",
    "  let s:count += 1",
    "  let g:divine_script_count = s:count",
    "  let g:divine_script_match = expand('<amatch>')",
    "endfunction",
    "augroup DivineScriptReplay",
    "  autocmd!",
    "  autocmd User DivineScript ++once call s:Record()",
    "augroup END",
  })
  local count = f.setup("script", { events = { "User" } })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineScript" })
  assert(count() == 1 and vim.g.divine_script_count == 1)
  assert(vim.g.divine_script_match == "DivineScript")
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineScript" })
  assert(vim.g.divine_script_count == 1)
end)

T["loads all event targets before replaying a shared new group"] = case(function(f)
  local loaded, seen = {}, {}
  f.triggers.register({
    load = function(id)
      loaded[#loaded + 1] = id
      local group = vim.api.nvim_create_augroup("DivineBatch", { clear = false })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "DivineBatch",
        callback = function()
          assert(#loaded == 2)
          seen[#seen + 1] = id
        end,
      })
    end,
  }, {
    a = { triggers = { events = { "User" } } },
    b = { triggers = { events = { "User" } } },
  })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineBatch" })
  assert(vim.deep_equal(loaded, { "a", "b" }), vim.inspect(loaded))
  assert(vim.deep_equal(seen, { "a", "b" }), vim.inspect(seen))
end)

T["preserves nested handlers and prevents recursive trigger loads"] = case(function(f)
  local loads, nested = 0, 0
  vim.api.nvim_create_autocmd(
    "User",
    { pattern = "DivineNested", callback = function() nested = nested + 1 end }
  )
  f.triggers.register({
    load = function()
      loads = loads + 1
      vim.api.nvim_exec_autocmds("User", { pattern = "DivineDuringLoad" })
      vim.api.nvim_create_autocmd("User", {
        group = vim.api.nvim_create_augroup("DivineNestedSource", { clear = true }),
        pattern = "DivineOuter",
        nested = true,
        callback = function() vim.cmd("doautocmd User DivineNested") end,
      })
    end,
  }, { event = { triggers = { events = { "User" } } } })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineOuter" })
  assert(loads == 1 and nested == 1, vim.inspect({ loads, nested }))
end)

T["supplements buffer read events in order with per-event exclusions"] = case(function(f)
  local seen, existing = {}, 0
  local group = vim.api.nvim_create_augroup("DivinePriorRead", { clear = true })
  vim.api.nvim_create_autocmd(
    "BufReadPre",
    { group = group, callback = function() existing = existing + 1 end }
  )
  f.triggers.register({
    load = function()
      for _, event in ipairs({ "BufReadPre", "BufReadPost" }) do
        vim.api.nvim_create_autocmd(event, {
          group = vim.api.nvim_create_augroup("DivineRead" .. event, { clear = false }),
          callback = function(a) seen[#seen + 1] = { a.event, a.buf, a.data } end,
        })
      end
      vim.api.nvim_create_autocmd(
        "BufReadPost",
        { group = group, callback = function() seen[#seen + 1] = { "shared-post" } end }
      )
    end,
  }, { event = { triggers = { events = { "BufReadPost" } } } })
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_exec_autocmds("BufReadPost", { buffer = buffer, data = { original = true } })
  assert(existing == 0)
  assert(#seen == 3 and seen[1][1] == "BufReadPre", vim.inspect(seen))
  assert(seen[2][1] == "shared-post" or seen[3][1] == "shared-post", vim.inspect(seen))
  for _, entry in ipairs(seen) do
    if entry[1] ~= "shared-post" then assert(entry[2] == buffer and entry[3].original) end
  end
end)

T["replays all FileType handlers after read supplements"] = case(function(f)
  local seen = {}
  local group = vim.api.nvim_create_augroup("DivineExistingFiletype", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "divinereplay",
    callback = function() seen[#seen + 1] = "existing" end,
  })
  f.triggers.register({
    load = function()
      local fresh = vim.api.nvim_create_augroup("DivineFiletypeRead", { clear = true })
      for _, event in ipairs({ "BufReadPre", "BufReadPost", "FileType" }) do
        vim.api.nvim_create_autocmd(
          event,
          { group = fresh, callback = function(a) seen[#seen + 1] = a.event end }
        )
      end
      vim.api.nvim_create_autocmd(
        "FileType",
        { callback = function() seen[#seen + 1] = "unscoped" end }
      )
    end,
  }, { event = { triggers = { filetypes = { "divinereplay" } } } })
  vim.bo.filetype = "divinereplay"
  assert(
    vim.deep_equal(seen, {
      "existing",
      "BufReadPre",
      "BufReadPost",
      "existing",
      "FileType",
      "unscoped",
    }),
    vim.inspect(seen)
  )
end)

T["preserves native callback removal"] = case(function(f)
  local calls, handle, group = 0
  f.triggers.register({
    load = function()
      group = vim.api.nvim_create_augroup("DivineCallbackRemoval", { clear = true })
      handle = vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "DivineRemove",
        callback = function(a)
          assert(a.id == handle and a.group == group)
          calls = calls + 1
          return true
        end,
      })
    end,
  }, { event = { triggers = { events = { "User" } } } })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineRemove" })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineRemove" })
  assert(calls == 1 and #vim.api.nvim_get_autocmds({ group = group }) == 0)
end)

T["retains unattempted event targets after a failure"] = case(function(f)
  local loaded = {}
  local _, activate = f.triggers.register({
    load = function(id)
      loaded[#loaded + 1] = id
      if id == "a" then error("load failed") end
      vim.api.nvim_create_user_command("DivineSurvivor", function() end, {})
    end,
  }, {
    a = { triggers = { events = { "User" } } },
    b = {
      triggers = {
        events = { "User" },
        commands = { "DivineSurvivor" },
        keys = { { lhs = "<F15>" } },
        modules = { "divine_survivor" },
      },
    },
  })
  activate()
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineFailure" })
  assert(vim.v.errmsg:find("failed", 1, true), vim.v.errmsg)
  assert(vim.deep_equal(loaded, { "a" }))
  assert(vim.fn.exists(":DivineSurvivor") == 2)
  assert(vim.fn.maparg("<F15>", "n") ~= "")
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineRecovery" })
  assert(vim.deep_equal(loaded, { "a", "b" }))
  assert(vim.fn.maparg("<F15>", "n") == "")
end)

T["retains unattempted current filetype targets after a failure"] = case(function(f)
  vim.bo.filetype = "divinefailure"
  local loaded = {}
  local _, activate = f.triggers.register({
    load = function(id)
      loaded[#loaded + 1] = id
      if id == "a" then error("load failed") end
      vim.api.nvim_create_user_command("DivineSurvivor", function() end, {})
    end,
  }, {
    a = { triggers = { filetypes = { "divinefailure" } } },
    b = {
      triggers = {
        filetypes = { "divinefailure" },
        commands = { "DivineSurvivor" },
        keys = { { lhs = "<F15>" } },
      },
    },
  })
  assert(not pcall(activate))
  assert(vim.deep_equal(loaded, { "a" }))
  assert(vim.fn.exists(":DivineSurvivor") == 2)
  assert(vim.fn.maparg("<F15>", "n") ~= "")
  activate()
  assert(vim.deep_equal(loaded, { "a" }))
  vim.cmd.DivineSurvivor()
  assert(vim.deep_equal(loaded, { "a", "b" }))
end)

T["reserves batch targets during nested events"] = case(function(f)
  local loaded, cleanup = {}, nil
  cleanup = f.triggers.register({
    load = function(id)
      loaded[#loaded + 1] = id
      if id == "a" then
        vim.api.nvim_exec_autocmds("BufEnter", {})
        assert(vim.deep_equal(loaded, { "a" }))
        -- Model runtime cleanup of a dependency or SCC peer.
        cleanup("b")
      end
    end,
  }, {
    a = { triggers = { events = { "User" } } },
    b = { triggers = { events = { "User", "BufEnter" } } },
    c = { triggers = { events = { "User" } } },
  })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineBatch" })
  assert(vim.deep_equal(loaded, { "a", "c" }), vim.inspect(loaded))
end)

T["retains independent targets when a prerequisite fails"] = case(function(f)
  local loaded = {}
  for _, name in ipairs({ "a", "b", "c" }) do
    f.write(name, "plugin/empty.lua", { "-- fixture" })
  end
  local controller = require("divine").setup({
    nodes = {
      a = { name = "a", triggers = { events = { "User" } } },
      b = {
        name = "b",
        before = function() error("prerequisite failed") end,
        triggers = { events = { "User" } },
      },
      c = {
        name = "c",
        triggers = { events = { "User" } },
        load = function() loaded[#loaded + 1] = "c" end,
      },
    },
    units = {
      { id = "a", members = { "a" }, dependencies = { "b" } },
      { id = "b", members = { "b" }, dependencies = {} },
      { id = "c", members = { "c" }, dependencies = {} },
    },
  })
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineFailure" })
  assert(vim.v.errmsg:find("failed", 1, true), vim.v.errmsg)
  assert(controller.states.a == "failed" and controller.states.b == "failed")
  assert(controller.states.c == "unloaded")
  vim.api.nvim_exec_autocmds("User", { pattern = "DivineRecovery" })
  assert(vim.deep_equal(loaded, { "c" }))
end)

T["shares canonical dispatchers when aliases fire"] = case(function(f)
  for _, pair in ipairs({
    { "BufRead", "BufReadPost" },
    { "BufWrite", "BufWritePre" },
    { "BufCreate", "BufAdd" },
    { "FileEncoding", "EncodingChanged" },
    { "uSeR", "User" },
  }) do
    local alias, canonical = unpack(pair)
    local before = #vim.api.nvim_get_autocmds({ event = canonical })
    local loaded, replayed = {}, {}
    local nodes = {
      a = { triggers = { events = { canonical } } },
      b = { triggers = { events = { canonical } } },
      c = { triggers = { events = { canonical } } },
    }
    local original = vim.deepcopy(nodes)
    f.triggers.register({
      load = function(id)
        loaded[#loaded + 1] = id
        vim.api.nvim_create_autocmd(canonical, {
          group = vim.api.nvim_create_augroup("DivineAlias" .. canonical, { clear = false }),
          callback = function(args)
            assert(#loaded == 3)
            assert(args.event == canonical and args.data.original)
            replayed[#replayed + 1] = id
          end,
        })
      end,
    }, nodes)
    assert(vim.deep_equal(nodes, original))
    assert(#vim.api.nvim_get_autocmds({ event = canonical }) == before + 1)
    vim.api.nvim_exec_autocmds(alias, { pattern = "DivineAlias", data = { original = true } })
    assert(vim.deep_equal(loaded, { "a", "b", "c" }), vim.inspect(loaded))
    assert(vim.deep_equal(replayed, { "a", "b", "c" }), vim.inspect(replayed))
    assert(#vim.api.nvim_get_autocmds({ event = canonical }) == before + 3)
    vim.api.nvim_del_augroup_by_name("DivineAlias" .. canonical)
  end
end)

T["cleans shared event dispatchers only after their last target"] = case(function(f)
  local loaded = {}
  local before = #vim.api.nvim_get_autocmds({ event = "BufReadPost" })
  local cleanup = f.triggers.register({ load = function(id) loaded[#loaded + 1] = id end }, {
    a = { triggers = { events = { "BufReadPost" } } },
    b = { triggers = { events = { "BufReadPost" } } },
  })
  cleanup("a")
  cleanup("a")
  assert(#vim.api.nvim_get_autocmds({ event = "BufReadPost" }) == before + 1)
  vim.api.nvim_exec_autocmds("BufRead", {})
  assert(vim.deep_equal(loaded, { "b" }))
  assert(#vim.api.nvim_get_autocmds({ event = "BufReadPost" }) == before)
end)

T["stops canonical event batches at the first failure"] = case(function(f)
  local loaded = {}
  local before = #vim.api.nvim_get_autocmds({ event = "BufReadPost" })
  f.triggers.register({
    load = function(id)
      loaded[#loaded + 1] = id
      if id == "a" then error("alias load failed") end
    end,
  }, {
    a = { triggers = { events = { "BufReadPost" } } },
    b = { triggers = { events = { "BufReadPost" } } },
    c = { triggers = { events = { "BufReadPost" } } },
  })
  vim.api.nvim_exec_autocmds("BufRead", {})
  assert(vim.v.errmsg:find("alias load failed", 1, true), vim.v.errmsg)
  assert(vim.deep_equal(loaded, { "a" }), vim.inspect(loaded))
  assert(#vim.api.nvim_get_autocmds({ event = "BufReadPost" }) == before + 1)
  vim.api.nvim_exec_autocmds("BUFREADPOST", {})
  assert(vim.deep_equal(loaded, { "a", "b", "c" }), vim.inspect(loaded))
  assert(#vim.api.nvim_get_autocmds({ event = "BufReadPost" }) == before)
end)

T["shares FileType dispatchers without widening filetype filters"] = case(function(f)
  local loaded = {}
  local before = #vim.api.nvim_get_autocmds({ event = "FileType" })
  f.triggers.register({ load = function(id) loaded[#loaded + 1] = id end }, {
    a = { triggers = { events = { "FileType" }, filetypes = { "divineyes" } } },
    b = { triggers = { filetypes = { "divineyes" } } },
    c = { triggers = { filetypes = { "divineno" } } },
  })
  assert(#vim.api.nvim_get_autocmds({ event = "FileType" }) == before + 1)
  vim.api.nvim_exec_autocmds("fIlEtYpE", { pattern = "divineyes" })
  assert(vim.deep_equal(loaded, { "a", "b" }), vim.inspect(loaded))
  assert(#vim.api.nvim_get_autocmds({ event = "FileType" }) == before + 1)
  vim.api.nvim_exec_autocmds("FileType", { pattern = "divineno" })
  assert(vim.deep_equal(loaded, { "a", "b", "c" }))
  assert(#vim.api.nvim_get_autocmds({ event = "FileType" }) == before)
end)

T["validates all declarations before registering events"] = case(function(f)
  local create, calls = vim.api.nvim_create_autocmd, 0
  vim.api.nvim_create_autocmd = function(...)
    calls = calls + 1
    return create(...)
  end
  local ok = pcall(f.triggers.register, { load = function() end }, {
    a = { triggers = { events = { "BufReadPost" }, commands = { "DivineValidation" } } },
    z = { triggers = { events = { "NotAnEvent" } } },
  })
  vim.api.nvim_create_autocmd = create
  assert(not ok and calls == 0)
  assert(vim.fn.exists(":DivineValidation") == 0)
end)

T["registers canonical events without temporary autocmd probes"] = case(function(f)
  local create, get, calls = vim.api.nvim_create_autocmd, vim.api.nvim_get_autocmds, 0
  vim.api.nvim_create_autocmd = function(...)
    calls = calls + 1
    return create(...)
  end
  vim.api.nvim_get_autocmds = function() error("unexpected event inspection") end
  local ok, err = pcall(f.triggers.register, { load = function() end }, {
    a = { triggers = { events = { "BufReadPost", "User" } } },
    b = { triggers = { events = { "BufReadPost" } } },
  })
  vim.api.nvim_create_autocmd, vim.api.nvim_get_autocmds = create, get
  assert(ok, err)
  assert(calls == 2)
end)

return T
