# Provisional input example, not an executable load plan.
/**
  Build illustrative declarations from a Nixpkgs package set.

  Timing remains unresolved for package shorthand, so the result is a resolver
  Configuration rather than a complete CompilationConfiguration.
  Named types are documented in ../docs/nix-types.md.

  # Type

  ```
  import ./examples/plugins.nix :: { pkgs :: PackageSet, ... } -> Configuration
  ```
*/
{ pkgs, ... }:
{
  plugins = [
    # A package alone is valid at both roots and dependencies.
    pkgs.vimPlugins.vim-repeat

    {
      plugin = pkgs.vimPlugins.telescope-nvim;
      lazy = true;
      dependPlugins = [
        pkgs.vimPlugins.plenary-nvim
        # Dependencies accept the same detailed definitions and further nesting.
        {
          plugin = pkgs.vimPlugins.vim-startuptime;
          lazy = false; # Load this at startup while keeping it in opt.
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
