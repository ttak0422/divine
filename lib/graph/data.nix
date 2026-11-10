/**
  Project a resolved graph into JSON-safe display data and Graphviz source.

  Never serialize arbitrary settings, Lua callbacks, checks or package metadata.
  Configuration membership is separate from dependency edges and SCC ownership.

  # Type

  ```
  import ./data.nix :: { lib :: AttrSet } -> Graph -> { data :: GraphView, dot :: String }
  ```
*/
{ lib }:
graph:
let
  vertices = graph.nodes // graph.configurationNodes;
  ids = builtins.attrNames vertices;
  indices = builtins.listToAttrs (
    lib.imap0 (index: id: {
      name = id;
      value = toString index;
    }) ids
  );
  owners = builtins.listToAttrs (
    lib.concatMap (
      unit:
      map (id: {
        name = id;
        value = unit;
      }) unit.configurations
    ) graph.units
  );
  nodes = map (
    id:
    let
      node = vertices.${id};
      isPackage = builtins.hasAttr id graph.nodes;
      unit = owners.${id};
    in
    {
      inherit id;
      svgId = "graph-node-${indices.${id}}";
      label = if isPackage then lib.getName node.package else "Packages: ${builtins.head node.origins}";
      kind = if isPackage then "package" else "configuration";
      doc = node.settings.doc or null;
      inherit (node) origins dependencies;
      members = if isPackage then [ id ] else node.members;
      root = builtins.elem id graph.roots;
      unitId = unit.id;
      unitStartup = unit.startup;
      inherit (unit) cyclic;
      physicalStartup =
        if isPackage then
          lib.any (candidate: candidate.startup && builtins.elem id candidate.members) graph.units
        else
          null;
    }
  ) ids;
  data = {
    inherit nodes;
    inherit (graph) roots units;
  };

  /**
    Quote one compact DOT label, preserving literal backslashes and quotes.

    Normalize control whitespace for display: JSON tab escapes are not DOT tab
    escapes. The data and inspector retain the original label unchanged.

    # Type

    ```
    quote :: String -> String
    ```
  */
  quote = value: builtins.toJSON (builtins.replaceStrings [ "\t" "\n" "\r" ] [ " " " " " " ] value);

  /**
    Return an internal DOT identifier unrelated to user-controlled names.

    # Type

    ```
    vertex :: String -> String
    ```
  */
  vertex = id: "n${indices.${id}}";
  nodeLines = map (
    node:
    "${vertex node.id} [id=${quote node.svgId}, label=${quote node.label}, "
    + "shape=${if node.kind == "package" then "box" else "component"}, "
    + "fillcolor=${quote (if node.kind == "package" then "#eef4ff" else "#f2eaff")}, "
    + "penwidth=${if node.root then "2.4" else "1.2"}];"
  ) nodes;
  clusters = lib.imap0 (
    index: unit:
    lib.optionalString unit.cyclic (
      "subgraph cluster_${toString index} {\n"
      + "label=${quote "Cycle · ${toString (builtins.length unit.configurations)} configuration(s)"}; "
      + "color=\"#d78c2c\"; style=\"rounded,dashed\"; bgcolor=\"#fff9ef\";\n"
      + lib.concatMapStringsSep "\n" (id: "${vertex id};") unit.configurations
      + "\n}"
    )
  ) graph.units;
  dependencies = lib.concatMap (
    node: map (dependency: "${vertex node.id} -> ${vertex dependency};") (lib.unique node.dependencies)
  ) nodes;
  memberships = lib.concatMap (
    node:
    if node.kind == "package" then
      [ ]
    else
      lib.imap0 (
        index: member:
        "${vertex node.id} -> ${vertex member} [style=dashed, color=\"#9c8ab9\", "
        + "arrowhead=none, constraint=false, label=${quote (toString (index + 1))}];"
      ) node.members
  ) nodes;
in
{
  inherit data;
  dot = lib.concatStringsSep "\n" (
    [
      "digraph divine {"
      "graph [rankdir=LR, bgcolor=transparent, pad=0.4, nodesep=0.5, ranksep=0.85, fontname=Helvetica, fontsize=12];"
      "node [style=\"rounded,filled\", color=\"#5974a0\", fontcolor=\"#172946\", fontname=Helvetica, fontsize=12, margin=\"0.18,0.12\"];"
      "edge [color=\"#71829d\", arrowsize=0.7, fontname=Helvetica, fontsize=10];"
    ]
    ++ nodeLines
    ++ clusters
    ++ dependencies
    ++ memberships
    ++ [ "}" ]
  );
}
