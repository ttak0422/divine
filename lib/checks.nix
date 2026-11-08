/**
  Construct checks without adding any test inputs to the runtime bundle.

  # Type

  ```
  import ./checks.nix :: { lib :: AttrSet, compile :: CompilationConfiguration -> Compiled, mkBundle :: AttrSet -> Derivation } -> AttrSet -> AttrsOf Derivation
  ```
*/
{
  lib,
  compile,
  mkBundle,
}:
{
  pkgs,
  configuration,
  bundle ? mkBundle { inherit pkgs configuration; },
  neovim ? pkgs.writeShellScriptBin "nvim" ''
    exec ${pkgs.neovim-unwrapped}/bin/nvim -u ${bundle}/init.lua "$@"
  '',
}:
let
  graph = (compile configuration).graph;
  context = { inherit pkgs bundle neovim; };
in
lib.mapAttrs (
  name: test:
  let
    # Use callPackage-style argument selection, without callPackage's override
    # machinery. { pkgs }: works; omitted optional arguments retain defaults.
    args = builtins.intersectAttrs (builtins.functionArgs test.run) context;
    result = test.run args;
  in
  if lib.isDerivation result then
    result
  else
    throw "divine checks: test '${name}' at ${test.origin} must return a derivation"
) graph.tests
