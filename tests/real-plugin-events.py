"""Exercise pinned plugins through native input/events, using compiled bundles."""

import contextlib
import logging
import os
from pathlib import Path
import sys
import time

import pynvim


# A normal qa! closes the RPC transport; pynvim logs that expected EOF noisily.
logging.getLogger("pynvim").setLevel(logging.CRITICAL)


@contextlib.contextmanager
def editor_for(bundle):
    editor = pynvim.attach(
        "child",
        argv=["nvim", "--embed", "--headless", "-n", "-i", "NONE", "-u", str(bundle / "init.lua")],
    )
    try:
        editor.ui_attach(80, 24, rgb=True)
        yield editor
    finally:
        try:
            editor.command("qa!")
        except (EOFError, OSError):
            pass
        editor.close()


def wait_for(check, description):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.01)
    raise AssertionError(description)


def lastplace(bundle, lazy):
    with editor_for(bundle) as editor:
        assert editor.vars.get("divine_lastplace_configs", 0) == (0 if lazy else 1)
        for index in range(2):
            path = Path(os.environ["HOME"]) / f"lastplace-{lazy}-{index}.txt"
            path.write_text("\n".join(f"line {line}" for line in range(1, 9)) + "\n")
            editor.command("edit " + editor.funcs.fnameescape(str(path)))
            assert editor.api.win_get_cursor(0) == [6, 1], "first file-read handoff lost the saved cursor"
            assert editor.vars["divine_reads"] == index + 1, "existing BufReadPre handler was replayed"
            assert editor.vars["divine_lastplace_configs"] == 1, "lastplace config repeated"
            assert editor.eval("v:errmsg") == ""
        if lazy:
            assert not editor.exec_lua("return package.loaded.cmp ~= nil")


def completion(bundle, lazy):
    with editor_for(bundle) as editor:
        assert editor.exec_lua("return package.loaded.cmp ~= nil") == (not lazy)
        assert editor.vars.get("divine_cmp_configs", 0) == (0 if lazy else 1)
        word = "divine_completion_word"

        def visible_candidate():
            return editor.exec_lua(
                'local cmp = require("cmp"); if not cmp.visible() then return false end; '
                'for _, entry in ipairs(cmp.get_entries()) do '
                'if entry:get_completion_item().label == ... then return true end end; return false',
                word,
            )

        def change_count():
            return editor.eval("get(g:, 'divine_TextChangedI', 0) + get(g:, 'divine_TextChangedP', 0)")

        # First insert, another insert in the same buffer, and explicit completion
        # of pre-existing text in a new buffer each exercise native key mappings.
        for index in range(3):
            manual = index == 2
            if manual:
                editor.command("enew!")
            editor.api.buf_set_lines(0, 0, -1, False, [word, "divine_comp" if manual else ""])
            editor.api.win_set_cursor(0, [2, 0])
            editor.input("A" if manual else "i")
            wait_for(lambda: editor.eval("mode()") == "i", "Insert mode was not entered")
            wait_for(
                lambda: bool(editor.funcs.maparg("<F13>", "i")),
                "first InsertEnter did not prepare cmp mappings",
            )
            assert editor.vars["divine_InsertEnter"] == index + 1, "existing InsertEnter handler repeated"
            if manual:
                editor.input("<F12>")
            else:
                # Separate native text-change events avoid depending on how a
                # whole RPC input burst is coalesced by Neovim.
                for text in ("divine_comp", "l"):
                    previous = change_count()
                    editor.input(text)
                    wait_for(
                        lambda: change_count() > previous,
                        "typed input did not emit TextChangedI/TextChangedP",
                    )
            wait_for(visible_candidate, "buffer completion candidate did not appear")
            editor.input("<F13>")
            wait_for(lambda: editor.api.get_current_line() == word, "cmp confirmation lost the first key")
            assert editor.vars["divine_cmp_configs"] == 1, "cmp config repeated"
            assert editor.exec_lua(
                'local count = 0; for _, source in pairs(require("cmp").get_registered_sources()) do '
                'if source.name == "buffer" then count = count + 1 end end; return count'
            ) == 1, "cmp-buffer registered more than once"
            editor.input("<Esc>")
            wait_for(lambda: editor.eval("mode()") == "n", "Insert mode did not exit")
            assert not editor.exec_lua('return require("cmp").visible()'), "completion popup survived InsertLeave"
            assert editor.eval("v:errmsg") == ""

        # Leave insert mode with a live popup, without first accepting an entry.
        editor.api.buf_set_lines(0, 0, -1, False, [word, "divine_comp"])
        editor.api.win_set_cursor(0, [2, 0])
        editor.input("A")
        wait_for(lambda: editor.eval("mode()") == "i", "cancel scenario did not enter Insert mode")
        editor.input("<F12>")
        wait_for(visible_candidate, "cancel scenario did not open completion")
        editor.input("<Esc>")
        wait_for(lambda: editor.eval("mode()") == "n", "cancel scenario did not exit Insert mode")
        wait_for(lambda: not editor.exec_lua('return require("cmp").visible()'), "InsertLeave left popup open")
        assert editor.api.get_current_line() == "divine_comp", "cancel accepted a completion entry"
        assert editor.vars["divine_InsertEnter"] == 4, "cancel replayed an existing InsertEnter observer"
        assert editor.vars["divine_cmp_configs"] == 1
        assert editor.eval("v:errmsg") == ""


if __name__ == "__main__":
    for path, lazy in zip(sys.argv[1:], (False, True), strict=True):
        bundle = Path(path)
        lastplace(bundle, lazy)
        completion(bundle, lazy)
        print(f"PASS: {'deferred' if lazy else 'startup'} lastplace and cmp native event handoff")
