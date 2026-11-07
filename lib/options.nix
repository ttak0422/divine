/**
  Define and evaluate compiler input options without merging plugin occurrences.

  # Type

  ```
  import ./options.nix :: { lib :: AttrSet } -> { normalize :: CompilationConfiguration -> CompilationConfiguration, definitionOptions :: AttrSet, rootOptions :: AttrSet }
  ```
*/
{ lib }:
let
  inherit (lib) mkOption types;
  package = types.addCheck types.attrs lib.isDerivation;
  luaSource = types.either types.str types.path;
  nonempty = types.addCheck types.str (value: value != "");
  conditions = types.either nonempty (types.listOf nonempty);
  key = types.either nonempty (
    types.addCheck types.attrs (
      value:
      value ? lhs
      && nonempty.check value.lhs
      &&
        builtins.attrNames (
          builtins.removeAttrs value [
            "lhs"
            "mode"
          ]
        ) == [ ]
      && builtins.elem (value.mode or "n") [
        "n"
        "i"
        "x"
        "s"
        "o"
        "t"
      ]
    )
  );
  # Recursive children are evaluated individually below, never merged by the
  # module system. Derivations are opaque and retain their original metadata.
  entries = types.listOf types.attrs;
  definitionOptions = {
    plugin = mkOption {
      type = package;
      description = "The plugin package; output path determines graph identity.";
    };
    lazy = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Load lazily. Null means unspecified; true is applied after all occurrences are merged.";
    };
    dependPlugins = mkOption {
      type = entries;
      default = [ ];
      description = "Explicit recursive plugin dependencies; package dependency metadata is ignored.";
    };
    extraPackages = mkOption {
      type = types.listOf package;
      default = [ ];
      description = "External tools required by this plugin.";
    };
    preConfig = mkOption {
      type = luaSource;
      description = "Lua text or file executed before loading.";
    };
    config = mkOption {
      type = luaSource;
      description = "Lua text or file executed after loading.";
    };
    load = mkOption {
      type = luaSource;
      description = "Custom Lua load operation, receiving the opt package name.";
    };
    onEvents = mkOption {
      type = conditions;
      default = [ ];
      description = "Neovim events that request loading.";
    };
    onCommands = mkOption {
      type = conditions;
      default = [ ];
      description = "Commands that request loading.";
    };
    onFiletypes = mkOption {
      type = conditions;
      default = [ ];
      description = "Buffer filetypes that request loading.";
    };
    onKeys = mkOption {
      type = types.either key (types.listOf key);
      default = [ ];
      description = "Keys that request loading; omitted mode means normal mode.";
    };
    onModules = mkOption {
      type = conditions;
      default = [ ];
      description = "Lua module namespaces that request loading.";
    };
  };
  rootOptions = {
    plugins = mkOption {
      type = entries;
      description = "Plugin packages or detailed definitions.";
    };
    extraPackages = mkOption {
      type = types.listOf package;
      default = [ ];
      description = "Global external tools.";
    };
    startupConfig = mkOption {
      type = luaSource;
      description = "Common Lua text or file executed during init.";
    };
    runtimePaths = mkOption {
      type = types.listOf (types.either types.path package);
      default = [ ];
      description = "Additional runtime trees, as paths or packages.";
    };
  };
  /**
    Validate supplied fields while retaining omission and original value shapes.

    Only the nullable timing default is materialized in occurrences. Other
    defaults are applied by the compiler after resolving repeated definitions.
    Do not combine occurrences with evalModules: its list merging and overrides
    differ from divine's equality/conflict and dependency-union policies.

    # Type

    ```
    evaluate :: AttrSet -> [String] -> AttrSet -> AttrSet
    ```
  */
  evaluate =
    options: required: value:
    let
      # This adapter accepts data, not module definitions. Reject property
      # wrappers before evalModules can unwrap them and alter supplied values.
      /**
        Reject module properties in values/lists, leaving packages opaque.

        # Type

        ```
        plain :: a -> Bool
        ```
      */
      plain =
        item:
        if builtins.isList item then
          lib.all plain item
        else if builtins.isAttrs item then
          lib.isDerivation item || !(item ? _type)
        else
          true;
      rawValid =
        builtins.isAttrs value
        && lib.all (
          name:
          builtins.hasAttr name options && options.${name}.type.check value.${name} && plain value.${name}
        ) (builtins.attrNames value);
      evaluated = lib.evalModules {
        modules = [
          { inherit options; }
          { config = value; }
        ];
      };
      supplied = lib.genAttrs (lib.unique (required ++ builtins.attrNames value)) (
        name: evaluated.config.${name}
      );
      # Force list element validation, but never traverse opaque packages or
      # arbitrary derivation attributes (including their dependencies).
      /**
        Force option/list validation without evaluating package internals.

        # Type

        ```
        force :: a -> Bool
        ```
      */
      force =
        item:
        if builtins.isList item then
          builtins.foldl' (acc: child: builtins.seq (force child) acc) true item
        else
          builtins.seq item true;
      checked = builtins.foldl' (acc: name: builtins.seq (force supplied.${name}) acc) true (
        builtins.attrNames supplied
      );
    in
    if !rawValid then
      throw "divine input: unsupported field, invalid type or module property in configuration data"
    else
      builtins.seq evaluated.config (builtins.seq checked supplied);
  /**
    Validate one finite definition and recursively adapt its explicit children.

    # Type

    ```
    definition :: (Package | CompilationDefinition) -> CompilationDefinition
    ```
  */
  definition =
    entry:
    let
      value = evaluate definitionOptions [ "plugin" "lazy" ] (
        if lib.isDerivation entry then { plugin = entry; } else entry
      );
    in
    value
    // lib.optionalAttrs (value ? dependPlugins) {
      dependPlugins = map definition value.dependPlugins;
    };
  /**
    Validate compiler input while leaving identity resolution to the resolver.

    # Type

    ```
    normalize :: CompilationConfiguration -> CompilationConfiguration
    ```
  */
  normalize =
    request:
    let
      value =
        if builtins.isAttrs request && request ? plugins then
          evaluate rootOptions [ "plugins" ] request
        else
          throw "divine input: expected a configuration containing plugins";
    in
    value // { plugins = map definition value.plugins; };
in
{
  inherit normalize definitionOptions rootOptions;
}
