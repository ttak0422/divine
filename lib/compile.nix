/**
  Construct the runtime-plan compiler from the Nixpkgs library and resolver.

  Named types are documented in ../docs/nix-types.md. The result contains Nix
  plan data and serialized Lua text, not executable Nix callback functions.

  # Type

  ```
  import ./compile.nix :: { lib :: AttrSet, resolve :: Configuration -> Graph } -> CompilationConfiguration -> Compiled
  ```
*/
{ lib, resolve }:
configuration:
let
  adapter = import ./options.nix { inherit lib; };
  graph = resolve (adapter.normalize configuration);

  /**
    Raise a compiler diagnostic; this function never returns a value.

    # Type

    ```
    fail :: String -> a
    ```
  */
  fail = message: throw "divine compiler: ${message}";
  allowed = [
    "lazy"
    "doc"
    "preConfig"
    "config"
    "load"
    "loadAfter"
    "onEvents"
    "onCommands"
    "onFiletypes"
    "onKeys"
    "onModules"
  ];

  /**
    Read Lua text directly or from a Nix path, with a diagnostic context.

    # Type

    ```
    source :: String -> (String | Path) -> String
    ```
  */
  source =
    context: value:
    if builtins.isString value then
      value
    else if builtins.isPath value then
      builtins.readFile value
    else
      fail "${context} must be Lua text or a Lua file path";

  /**
    Wrap Lua source in a function expression for the Lua serializer.

    Arguments are the diagnostic context, Lua parameter text and Lua source.
    LuaInline is an attribute set with _type and expr, not a Nix function.

    # Type

    ```
    callback :: String -> String -> (String | Path) -> LuaInline
    ```
  */
  callback =
    context: arguments: value:
    lib.generators.mkLuaInline "function(${arguments})\n${source context value}\nend";
  triggerForms = import ./trigger-forms.nix { inherit lib fail; };

  /**
    Compile shared settings without assigning package identity.

    # Type

    ```
    compileSettings :: String -> AttrSet -> AttrSet
    ```
  */
  compileSettings =
    id: settings:
    let
      unknown = builtins.filter (field: !(builtins.elem field allowed)) (builtins.attrNames settings);
    in
    if unknown != [ ] then
      fail "unsupported fields for '${id}': ${lib.concatStringsSep ", " unknown}"
    else
      {
        triggers = {
          events = lib.unique (triggerForms.onEvents (settings.onEvents or [ ]));
          commands = lib.unique (triggerForms.onCommands (settings.onCommands or [ ]));
          filetypes = lib.unique (triggerForms.onFiletypes (settings.onFiletypes or [ ]));
          keys = triggerForms.onKeys (settings.onKeys or [ ]);
          modules = lib.unique (triggerForms.onModules (settings.onModules or [ ]));
        };
      }
      // lib.optionalAttrs (settings ? preConfig) { before = callback "preConfig" "" settings.preConfig; }
      // lib.optionalAttrs (settings ? config) { after = callback "config" "" settings.config; }
      // lib.optionalAttrs (settings ? load) { load = callback "load" "name" settings.load; };
  nodes = lib.mapAttrs (
    id: node:
    compileSettings id node.settings
    // {
      # An output-path hash prevents equal display names from colliding in opt.
      name = "divine-${builtins.hashString "sha256" id}";
    }
    // lib.optionalAttrs (node.settings.loadAfter or false) { after_path = "${node.package}/after"; }
  ) graph.nodes;
  configurations = lib.mapAttrs (
    id: node: compileSettings id node.settings // { inherit (node) members; }
  ) graph.configurationNodes;
  unknownRoot = builtins.attrNames (
    builtins.removeAttrs graph.metadata [
      "startupConfig"
      "runtimePaths"
    ]
  );
  runtimePaths = graph.metadata.runtimePaths or [ ];
  plan = {
    inherit nodes;
    units = map (
      unit:
      {
        inherit (unit) id members dependencies;
      }
      // lib.optionalAttrs (configurations != { }) { inherit (unit) configurations; }
    ) graph.units;
    startup_units = graph.startupUnits;
  }
  // lib.optionalAttrs (configurations != { }) { inherit configurations; }
  // lib.optionalAttrs (graph.metadata ? startupConfig) {
    startup = callback "startupConfig" "" graph.metadata.startupConfig;
  };
  checked =
    if unknownRoot != [ ] then
      fail "unsupported root fields: ${lib.concatStringsSep ", " unknownRoot}"
    else if
      !builtins.isList runtimePaths || !lib.all (p: builtins.isPath p || lib.isDerivation p) runtimePaths
    then
      fail "runtimePaths must be a list of paths or packages"
    else
      builtins.deepSeq plan plan;
in
{
  inherit graph runtimePaths;
  plan = checked;
  lua = lib.generators.toLua { } checked;
}
