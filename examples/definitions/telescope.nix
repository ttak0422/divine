/**
  Keep a plugin's configuration, documentation and build-time check together.

  # Type

  ```
  import ./telescope.nix :: { pkgs :: PackageSet } -> AttrsOf Definition
  ```
*/
{ pkgs }:
{
  telescope = {
    plugin = pkgs.vimPlugins.telescope-nvim;
    dependPlugins = [ pkgs.vimPlugins.plenary-nvim ];
    extraPackages = [
      pkgs.ripgrep
      pkgs.fd
    ];
    config = # lua
      ''
        require("telescope").setup({})
      '';
    doc = ''
      Telescope provides interactive pickers. Run `:Telescope find_files` to
      search files. This configuration loads Telescope at startup.
    '';
    test =
      { pkgs, neovim }:
      let
        python = pkgs.python3.withPackages (ps: [ ps.pynvim ]);
      in
      pkgs.runCommand "telescope-rpc" { nativeBuildInputs = [ python ]; } ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_DATA_HOME="$HOME/data"
        export XDG_STATE_HOME="$HOME/state"
        export XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$HOME"
        python - <<'PY'
        import pynvim

        # Each attachment starts a new editor with the generated configuration.
        # This checks RPC access and startup across two processes, not picker UI.
        for _ in range(2):
            editor = pynvim.attach("child", argv=[
                "${neovim}/bin/nvim", "--embed", "--headless", "-n", "-i", "NONE"
            ])
            try:
                assert editor.exec_lua(
                    'return type(require("telescope.builtin").find_files)'
                ) == "function"
            finally:
                try:
                    editor.command("qa!")
                except EOFError:
                    pass
                editor.close()
        PY
        touch "$out"
      '';
  };
}
