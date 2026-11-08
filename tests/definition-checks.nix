{ pkgs }:
let
  api = import ../lib { inherit (pkgs) lib; };
  plugin = pkgs.runCommand "inline-check-fixture" { } ''
    mkdir -p "$out/plugin"
    echo 'let g:divine_inline_fixture = 1' > "$out/plugin/fixture.vim"
  '';
  # A unique test-only input makes closure leakage observable even when the
  # runtime itself has transitive Python references.
  testOnly = pkgs.writeText "divine-test-only-sentinel" "test dependency";
  configuration.plugins = [
    {
      inherit plugin;
      doc = "Inline documentation fixture.";
      config = # lua
        ''
          vim.keymap.set("i", "jj", "<Esc>")
        '';
      test = {
        inline-package =
          { pkgs }:
          pkgs.runCommand "inline-package-check" { } ''
            test -f ${plugin}/plugin/fixture.vim
            touch "$out"
          '';
        inline-input =
          {
            pkgs,
            bundle,
            neovim,
          }:
          let
            python = pkgs.python3.withPackages (ps: [ ps.pynvim ]);
            script = pkgs.writeText "inline-input.py" ''
              import pathlib
              import sys
              import time
              import pynvim

              def start():
                  nvim = pynvim.attach("child", argv=[sys.argv[1], "--embed", "--headless", "-n", "-i", "NONE"])
                  assert nvim.vars["divine_inline_fixture"] == 1
                  assert nvim.eval("v:errmsg") == ""
                  return nvim

              def wait(nvim, predicate):
                  end = time.monotonic() + 10
                  while time.monotonic() < end:
                      if predicate():
                          return
                      time.sleep(0.02)
                  raise AssertionError((nvim.eval("mode()"), nvim.current.buffer[:]))

              def stop(nvim):
                  try:
                      nvim.command("qa!")
                  except EOFError:
                      pass
                  finally:
                      nvim.close()

              nvim = start()
              try:
                  nvim.input("iinline-inputjj")
                  wait(nvim, lambda: nvim.current.line == "inline-input" and nvim.eval("mode()") == "n")
                  state = pathlib.Path(nvim.call("stdpath", "state")) / "inline-check.txt"
                  state.parent.mkdir(parents=True, exist_ok=True)
                  state.write_text(nvim.current.line)
              finally:
                  stop(nvim)

              nvim = start()
              try:
                  state = pathlib.Path(nvim.call("stdpath", "state")) / "inline-check.txt"
                  assert state.read_text() == "inline-input"
                  nvim.input("/first-command-line")
                  wait(nvim, lambda: nvim.call("getcmdline") == "first-command-line")
                  nvim.input("<Esc>")
              finally:
                  stop(nvim)
            '';
          in
          assert builtins.length (builtins.attrNames bundle.graph.nodes) == 1;
          pkgs.runCommand "inline-input-check" { } ''
            export HOME="$TMPDIR/home"
            export XDG_CONFIG_HOME="$TMPDIR/config" XDG_DATA_HOME="$TMPDIR/data"
            export XDG_STATE_HOME="$TMPDIR/state" XDG_CACHE_HOME="$TMPDIR/cache"
            export NVIM_APPNAME=divine-inline-test
            mkdir -p "$HOME"
            test -f ${testOnly}
            ${python}/bin/python ${script} ${neovim}/bin/nvim
            touch "$out"
          '';
      };
    }
  ];
  bundle = api.mkBundle { inherit pkgs configuration; };
  docs = api.mkDocs { inherit pkgs configuration; };
  closure = pkgs.closureInfo { rootPaths = [ bundle ]; };
  checks = api.mkChecks { inherit pkgs configuration bundle; };
in
checks
// {
  inline-docs-and-closure = pkgs.runCommand "inline-docs-and-closure" { } ''
    grep -F 'Inline documentation fixture.' ${docs}
    grep -F 'plugins[0]' ${docs}
    ! grep -F 'Inline documentation fixture.' ${bundle}/plan.lua
    ! grep -F 'inline-input' ${bundle}/plan.lua
    ! grep -Fx ${pkgs.lib.escapeShellArg (builtins.unsafeDiscardStringContext (toString testOnly))} ${closure}/store-paths
    touch "$out"
  '';
}
