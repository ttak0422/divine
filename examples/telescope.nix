/**
  Build the runnable example from the shared Telescope and project cartridges.

  # Type

  ```
  import ./examples/telescope.nix :: { pkgs :: PackageSet, lib :: AttrSet } -> Derivation
  ```
*/
{ pkgs, lib }:
lib.mkBundle {
  inherit pkgs;
  configuration = import ./cartridges { inherit pkgs; };
}
