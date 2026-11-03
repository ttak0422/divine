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
  inspectDefinitions =
    entries:
    if builtins.isList entries then
      map inspect entries
    else
      throw "divine prototype: expected a list of plugin definitions";

  # TODO(API): names and shape are provisional, preserve unrecognized metadata.
  # TODO(IDENTITY): repeated occurrences are retained; do not infer a merge policy.
  # TODO(CYCLES): choose finite graph input and SCC planning before accepting cyclic values.
  # TODO(PLAN): this inspector is not an executable load plan.
}
