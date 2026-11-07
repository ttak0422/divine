{ lib, resolve }:
configuration:
let
  graph = resolve configuration;
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
  source =
    context: value:
    if builtins.isString value then
      value
    else if builtins.isPath value then
      builtins.readFile value
    else
      fail "${context} must be Lua text or a Lua file path";
  callback =
    context: arguments: value:
    lib.generators.mkLuaInline "function(${arguments})\n${source context value}\nend";
  conditions =
    context: value:
    let
      values = if builtins.isString value then [ value ] else value;
    in
    if builtins.isList values && lib.all (v: builtins.isString v && v != "") values then
      lib.unique values
    else
      fail "${context} must be a string or a list of nonempty strings";
  keys =
    context: value:
    let
      entries = if builtins.isString value || builtins.isAttrs value then [ value ] else value;
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
