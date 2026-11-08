/**
  Compose ordinary Nix definition groups, registering each full definition once.

  The caller supplies its own Goda package. The cross-group edge is illustrative,
  not a statement that the real plugin depends on Telescope.

  # Type

  ```
  import ./examples/definitions :: { pkgs :: PackageSet, packages :: { goda :: Package } } -> Configuration
  ```
*/
{ pkgs, packages }:
let
  telescope = import ./telescope.nix { inherit pkgs; };
  goda = import ./goda.nix { inherit packages telescope; };
in
{
  plugins = builtins.attrValues telescope ++ builtins.attrValues goda;
  startupConfig = # lua
    ''
      vim.g.mapleader = " "
    '';
}
