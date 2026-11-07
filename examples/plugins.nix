# Provisional input example, not an executable load plan.
/**
  Build illustrative declarations from a Nixpkgs package set.

  Package shorthand loads at startup. This example selectively defers one
  plugin while keeping its dependencies available from startup.
  Named types are documented in ../docs/nix-types.md.

  # Type

  ```
  import ./examples/plugins.nix :: { pkgs :: PackageSet, ... } -> Configuration
  ```
*/
{ pkgs, ... }:
{
  plugins = [
    # A package alone loads at startup at both roots and dependencies.
    pkgs.vimPlugins.vim-repeat

    {
      plugin = pkgs.vimPlugins.telescope-nvim;
      lazy = true; # Explicit opt-in to deferred loading.
      dependPlugins = [
        pkgs.vimPlugins.plenary-nvim
        # Dependencies accept the same detailed definitions and further nesting.
        {
          plugin = pkgs.vimPlugins.vim-startuptime;
          # Omit lazy to load at startup while keeping this in opt.
          preConfig = # lua
            ''
              vim.g.startuptime_tries = 10
            '';
          config = # lua
            ''
              vim.keymap.set("n", "<leader>st", "<cmd>StartupTime<cr>")
            '';
          dependPlugins = [ pkgs.vimPlugins.vim-repeat ];
        }
      ];
      onCommands = [ "Telescope" ];
      extraPackages = [
        pkgs.ripgrep
        pkgs.fd
      ];
      config = # lua
        ''
          require("telescope").setup({})
        '';
    }
  ];
}
