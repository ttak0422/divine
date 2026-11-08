/**
  Compose ordinary Nix cartridges, registering each full definition once.

  The project cartridge enables the Telescope projects picker.

  # Type

  ```
  import ./examples/cartridges :: { pkgs :: PackageSet } -> Configuration
  ```
*/
{ pkgs }:
let
  telescope = import ./telescope.nix { inherit pkgs; };
  project = import ./project.nix { inherit pkgs telescope; };
in
{
  plugins = builtins.concatLists (
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
