/**
  Compose a complete configuration from cartridges and direct plugin declarations.

  The project cartridge enables the Telescope projects picker.

  # Type

  ```
  import ./examples/example.nix :: { pkgs :: PackageSet } -> Configuration
  ```
*/
{ pkgs }:
let
  telescope = import ./cartridges/telescope.nix { inherit pkgs; };
  project = import ./cartridges/project.nix { inherit pkgs telescope; };
in
{
  plugins = [
    # Simple plugins can be declared directly, without a cartridge.
    pkgs.vimPlugins.vim-repeat
  ]
  ++ builtins.concatLists (
    map builtins.attrValues [
      telescope
      project
    ]
  );
  startupConfig = # lua
    ''
      vim.g.mapleader = " "
    '';
}
