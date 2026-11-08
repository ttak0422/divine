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
    packages = mkOption {
      type = types.addCheck (types.listOf package) (values: values != [ ]);
      description = "Ordered packages sharing one load lifecycle and configuration; alternative to plugin.";
    };
    lazy = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Load lazily. Null means unspecified; false is applied after all occurrences are merged.";
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
    doc = mkOption {
      type = types.str;
      description = "Markdown documentation, emitted separately from the runtime bundle.";
    };
    test = mkOption {
      type = types.addCheck types.anything builtins.isFunction;
      description = "One check function, named from the plugin package with lib.getName.";
    };
    tests = mkOption {
      type = types.addCheck types.attrs (value: lib.all builtins.isFunction (builtins.attrValues value));
      description = "Globally named check functions; each returns a derivation using pkgs, bundle or neovim.";
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
    loadAfter = mkOption {
      type = types.bool;
      description = "Explicitly load after/plugin and initialized after/ftdetect scripts; after/plugin completes before configuration at startup and on deferred loading.";
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
          builtins.hasAttr name options
          && options.${name}.type.check value.${name}
          && (name == "tests" || plain value.${name})
        ) (builtins.attrNames value);
      /**
        Hide a package's module discriminator in a temporary validation view.
        The returned configuration retains the original package, unchanged.

        # Type

        ```
        validationView :: a -> a
        ```
      */
      validationView =
        item:
        if builtins.isList item then
          map validationView item
        else if lib.isDerivation item then
          builtins.removeAttrs item [ "_type" ]
        else
          item;
      evaluated = lib.evalModules {
        modules = [
          { inherit options; }
          {
            # The callback map is already checked above. Keep arbitrary test
            # names (including _type) opaque to module-property interpretation.
            config = lib.mapAttrs (name: item: if name == "tests" then { } else validationView item) value;
          }
        ];
      };
      names = lib.unique (required ++ builtins.attrNames value);
      validated = lib.genAttrs names (name: evaluated.config.${name});
      supplied = lib.genAttrs names (
        name: if builtins.hasAttr name value then value.${name} else validated.${name}
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
      checked = builtins.foldl' (acc: name: builtins.seq (force validated.${name}) acc) true (
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
      raw = if lib.isDerivation entry then { plugin = entry; } else entry;
      value =
        if !builtins.isAttrs raw || (raw ? plugin) == (raw ? packages) then
          throw "divine input: use exactly one of plugin and nonempty packages"
        else if raw ? packages && raw ? test then
          throw "divine input: packages definitions require explicitly named tests"
        else if builtins.isAttrs raw && raw ? test && raw ? tests then
          throw "divine input: a definition cannot contain both test and tests"
        else if builtins.isAttrs raw && raw ? test && !builtins.isFunction raw.test then
          throw "divine input: test must be a function; use tests.<name> for named checks"
        else
          evaluate definitionOptions [ (if raw ? packages then "packages" else "plugin") "lazy" ] raw;
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
