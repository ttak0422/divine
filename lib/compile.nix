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
  graph = resolve configuration;
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
    "preConfig"
    "config"
    "load"
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
  /**
    Normalize one nonempty condition or a list into unique condition strings.

    The first argument is the diagnostic context. An empty list is valid;
    empty strings and non-string list elements throw.

    # Type

    ```
    conditions :: String -> (String | [String]) -> [String]
    ```
  */
  conditions =
    context: value:
    let
      values = if builtins.isString value then [ value ] else value;
    in
    if builtins.isList values && lib.all (v: builtins.isString v && v != "") values then
      lib.unique values
    else
      fail "${context} must be a string or a list of nonempty strings";
  /**
    Normalize one key declaration or a list of declarations.

    The first argument is the diagnostic context. An empty list is valid.

    # Type

    ```
    keys :: String -> (KeyInput | [KeyInput]) -> [Key]
    ```
  */
  keys =
    context: value:
    let
      entries = if builtins.isString value || builtins.isAttrs value then [ value ] else value;
      /**
        Normalize one nonempty key, defaulting an omitted mode to normal mode.

        Only lhs and mode are accepted in an attribute-set declaration.

        # Type

        ```
        normalize :: KeyInput -> Key
        ```
      */
      normalize =
        entry:
        if builtins.isString entry && entry != "" then
          {
            lhs = entry;
            mode = "n";
          }
        else if
          builtins.isAttrs entry
          && entry ? lhs
          && builtins.isString entry.lhs
          && entry.lhs != ""
          &&
            builtins.attrNames (
              builtins.removeAttrs entry [
                "lhs"
                "mode"
              ]
            ) == [ ]
          && builtins.elem (entry.mode or "n") [
            "n"
            "i"
            "x"
            "s"
            "o"
            "t"
          ]
        then
          {
            inherit (entry) lhs;
            mode = entry.mode or "n";
          }
        else
          fail "${context} entries need lhs and an optional single mode (n/i/x/s/o/t)";
    in
    if builtins.isList entries then
      map normalize entries
    else
      fail "${context} must be a key or a list of keys";
  nodes = lib.mapAttrs (
    id: node:
    let
      settings = node.settings;
      unknown = builtins.filter (field: !(builtins.elem field allowed)) (builtins.attrNames settings);
    in
    if unknown != [ ] then
      fail "unsupported fields for '${id}': ${lib.concatStringsSep ", " unknown}"
    else
      {
        # An output-path hash prevents equal display names from colliding in opt.
        name = "divine-${builtins.hashString "sha256" id}";
        triggers = {
          events = conditions "onEvents" (settings.onEvents or [ ]);
          commands = conditions "onCommands" (settings.onCommands or [ ]);
          filetypes = conditions "onFiletypes" (settings.onFiletypes or [ ]);
          keys = keys "onKeys" (settings.onKeys or [ ]);
          modules = conditions "onModules" (settings.onModules or [ ]);
        };
      }
      // lib.optionalAttrs (settings ? preConfig) { before = callback "preConfig" "" settings.preConfig; }
      // lib.optionalAttrs (settings ? config) { after = callback "config" "" settings.config; }
      // lib.optionalAttrs (settings ? load) { load = callback "load" "name" settings.load; }
  ) graph.nodes;
  unknownRoot = builtins.attrNames (
    builtins.removeAttrs graph.metadata [
      "startupConfig"
      "runtimePaths"
    ]
  );
  runtimePaths = graph.metadata.runtimePaths or [ ];
  plan = {
    inherit nodes;
    units = map (unit: { inherit (unit) id members dependencies; }) graph.units;
    startup_units = graph.startupUnits;
  }
  // lib.optionalAttrs (graph.metadata ? startupConfig) {
    startup = callback "startupConfig" "" graph.metadata.startupConfig;
  };
  checked =
    if unknownRoot != [ ] then
      fail "unsupported root fields: ${lib.concatStringsSep ", " unknownRoot}"
    else if graph.unresolvedTiming != [ ] then
      fail "load timing remains unresolved; declare lazy explicitly for: ${lib.concatStringsSep ", " graph.unresolvedTiming}"
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
