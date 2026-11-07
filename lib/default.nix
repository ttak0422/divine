{ lib }:
let
  inspect =
    entry:
    let
      definition = if lib.isDerivation entry then { plugin = entry; } else entry;
      dependencies = definition.dependPlugins or [ ];
    in
    if
      !builtins.isAttrs definition || !(definition ? plugin) || !lib.isDerivation definition.plugin
    then
      throw "divine prototype: expected a package or a definition containing a package"
    else if !builtins.isList dependencies then
      throw "divine prototype: dependency definitions must be a list"
    else if definition ? lazy && !builtins.isBool definition.lazy then
      throw "divine prototype: an explicit load-timing flag must be boolean"
    else
      {
        inherit definition;
        dependencies = map inspect dependencies;
      };
  inspectDefinitions =
    entries:
    if builtins.isList entries then
      map inspect entries
    else
      throw "divine prototype: expected a list of plugin definitions";
  resolve = import ./resolve.nix { inherit lib inspectDefinitions; };
  compile = import ./compile.nix { inherit lib resolve; };
in
{
  /**
    Inspect finite package/definition trees without assigning load defaults.

    # Type

    ```
    inspectDefinitions :: [Package | Definition] -> [InspectedDefinition]
    ```

    # Arguments

    entries
    : Provisional definitions; dependencies use the same recursive form.
  */
  inherit inspectDefinitions;

  /**
    Resolve finite declarations into an opt-only graph and dependency-first SCC units.

    All names and policies are provisional; see docs/resolution.md for review decisions.

    # Type

    ```
    resolve :: { plugins :: [Package | Definition], extraPackages ? [Package], ... } -> Graph
    ```
  */
  inherit resolve;

  /**
    Compile explicitly timed declarations into a provisional Lua runtime plan.

    # Type

    ```
    compile :: Configuration -> { graph, plan, lua, runtimePaths }
    ```
  */
  inherit compile;

  /**
    Build an opt-only runtime tree with an init.lua entry point.

    # Type

    ```
    mkBundle :: { pkgs :: PackageSet, configuration :: Configuration } -> Derivation
    ```
  */
  mkBundle = import ./bundle.nix { inherit lib compile; };
}
