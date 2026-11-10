/**
  Build a standalone offline HTML dependency graph from configuration docs.

  Graphviz is a build-time tool only. The output does not change the runtime
  bundle or evaluate check functions. All embedded user data is inert text.

  # Type

  ```
  import ./graph.nix :: { lib :: AttrSet, compile :: CompilationConfiguration -> Compiled } -> { pkgs :: PackageSet, configuration :: CompilationConfiguration } -> Derivation
  ```
*/
{ lib, compile }:
{ pkgs, configuration }:
let
  compiled = compile configuration;
  graph = builtins.seq compiled.plan compiled.graph;
  view = import ./graph/data.nix { inherit lib; } graph;

  # HTML script elements are raw-text contexts, even for application/json.
  json = builtins.replaceStrings [ "<" ">" "&" ] [ "\\u003c" "\\u003e" "\\u0026" ] (
    builtins.toJSON view.data
  );
  parts = map (
    part:
    builtins.replaceStrings
      [ "@@GRAPH_DATA@@" "@@GRAPH_SCRIPT@@" ]
      [ json (builtins.readFile ./graph/viewer.js) ]
      part
  ) (lib.splitString "@@GRAPH_SVG@@" (builtins.readFile ./graph/viewer.html));
  prefix = pkgs.writeText "divine-graph-prefix.html" (builtins.head parts);
  suffix = pkgs.writeText "divine-graph-suffix.html" (builtins.elemAt parts 1);
  dot = pkgs.writeText "divine-graph.dot" view.dot;
in
assert builtins.length parts == 2;
pkgs.runCommand "divine-graph.html" { nativeBuildInputs = [ pkgs.graphviz ]; } ''
  dot -Tsvg ${dot} > graph.svg
  cat ${prefix} > "$out"
  sed -n '/<svg/,$p' graph.svg >> "$out"
  cat ${suffix} >> "$out"
''
