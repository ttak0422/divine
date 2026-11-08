/**
  Generate documentation independently of runtime files and check derivations.

  # Type

  ```
  import ./docs.nix :: { lib :: AttrSet, compile :: CompilationConfiguration -> Compiled } -> { pkgs :: PackageSet, configuration :: CompilationConfiguration } -> Derivation
  ```
*/
{ lib, compile }:
{ pkgs, configuration }:
let
  graph = (compile configuration).graph;
  documented = lib.filterAttrs (_: node: node.settings ? doc) graph.nodes;
  sections = lib.mapAttrsToList (
    id: node:
    lib.concatStringsSep "\n\n" [
      "## ${lib.getName node.package}"
      "Package: `${id}`"
      ("Declarations: " + lib.concatMapStringsSep ", " (origin: "`${origin}`") node.origins)
      node.settings.doc
    ]
  ) documented;
in
pkgs.writeText "divine-configuration.md" (
  lib.concatStringsSep "\n\n" ([ "# Configuration" ] ++ sections) + "\n"
)
