{ lib }:
let
  api = import ../lib { inherit lib; };
  adapter = import ../lib/options.nix { inherit lib; };
  a = {
    type = "derivation";
    outPath = "/nix/store/00000000000000000000000000000000-a";
  };
  b = a // {
    outPath = "/nix/store/00000000000000000000000000000000-b";
  };
  timing = entries: (api.resolve { plugins = entries; }).nodes.${a.outPath}.settings.lazy;
  invalid = request: {
    expr = builtins.deepSeq (api.compile request).lua true;
    expectedError.type = "ThrownError";
  };
in
{
  testRejectTimingModuleProperty = invalid {
    plugins = [
      {
        plugin = a;
        lazy = lib.mkDefault false;
      }
    ];
  };
  testRejectKeyModuleProperty = invalid {
    plugins = [
      {
        plugin = a;
        onKeys = {
          lhs = "a";
          _type = "override";
          priority = 1;
          content = "x";
        };
      }
    ];
  };
  testRejectTriggerModuleProperty = invalid {
    plugins = [
      {
        plugin = a;
        onCommands = lib.mkMerge [ [ "Example" ] ];
      }
    ];
  };
  testRejectListModuleProperty = invalid {
    plugins = [
      {
        plugin = a;
        onCommands = [ (lib.mkDefault "Example") ];
      }
    ];
  };
  testRejectDependencyModuleProperty = invalid {
    plugins = [
      {
        plugin = a;
        dependPlugins = [ (lib.mkDefault b) ];
      }
    ];
  };
  testPreservePackageModuleMetadata = {
    expr =
      let
        original = a // {
          _type = "override";
          priority = 1;
          content = b;
        };
        result = api.compile {
          plugins = [ original ];
          extraPackages = [ original ];
        };
      in
      builtins.deepSeq result.lua (
        result.graph.nodes.${a.outPath}.package == original
        && (builtins.head result.graph.extraPackages) == original
      );
    expected = true;
  };
  testDoNotEvaluatePackageModuleMetadata = {
    expr =
      builtins.length
        (api.compile { plugins = [ (a // { _type = throw "opaque metadata"; }) ]; }).plan.units;
    expected = 1;
  };
  testNullableSchema = {
    expr =
      adapter.definitionOptions.lazy.default == null
      && adapter.definitionOptions.lazy.type.check null
      && adapter.definitionOptions.lazy.type.check false;
    expected = true;
  };
  testNullTimingDefault = {
    expr = timing [
      {
        plugin = a;
        lazy = null;
      }
    ];
    expected = false;
  };
  testNullAndExplicitBothOrders = {
    expr =
      lib.all
        (
          flag:
          lib.all (entries: timing entries == flag) [
            [
              {
                plugin = a;
                lazy = null;
              }
              {
                plugin = a;
                lazy = flag;
              }
            ]
            [
              {
                plugin = a;
                lazy = flag;
              }
              {
                plugin = a;
                lazy = null;
              }
            ]
          ]
        )
        [
          true
          false
        ];
    expected = true;
  };
  testNullDoesNotHideConflict = invalid {
    plugins = [
      {
        plugin = a;
        lazy = null;
      }
      {
        plugin = a;
        lazy = true;
      }
      {
        plugin = a;
        lazy = false;
      }
    ];
  };
  testNestedNullAndStartup = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = b;
            dependPlugins = [
              {
                plugin = a;
                lazy = null;
              }
            ];
          }
          {
            plugin = a;
            lazy = false;
          }
        ];
      }).plan.startup_units;
    expected = [
      a.outPath
      b.outPath
    ];
  };
  testNoSyntheticTriggerConflict = {
    expr =
      (api.compile {
        plugins = [
          a
          {
            plugin = a;
            onCommands = "Example";
          }
        ];
      }).plan.nodes.${a.outPath}.triggers.commands;
    expected = [ "Example" ];
  };
  testPreserveRawConflict = invalid {
    plugins = [
      {
        plugin = a;
        onCommands = "Example";
      }
      {
        plugin = a;
        onCommands = [ "Example" ];
      }
    ];
  };
  testOpaquePackageMetadata = {
    expr =
      builtins.length
        (api.compile {
          plugins = [ (a // { dependencies = throw "must not inspect package metadata"; }) ];
        }).plan.units;
    expected = 1;
  };
  testRejectNestedUnknown = invalid {
    plugins = [
      {
        plugin = b;
        dependPlugins = [
          {
            plugin = a;
            unknown = true;
          }
        ];
      }
    ];
  };
  testRejectInvalidNestedTools = invalid {
    plugins = [
      {
        plugin = a;
        extraPackages = [ false ];
      }
    ];
  };
  testRejectNullConfig = invalid {
    plugins = [
      {
        plugin = a;
        config = null;
      }
    ];
  };
  testRejectNullTrigger = invalid {
    plugins = [
      {
        plugin = a;
        onEvents = null;
      }
    ];
  };
  testRejectUnknownKey = invalid {
    plugins = [
      {
        plugin = a;
        onKeys = {
          lhs = "x";
          unknown = true;
        };
      }
    ];
  };
  testRejectInvalidStartup = invalid {
    plugins = [ ];
    startupConfig = false;
  };
  testRejectMissingPlugins = invalid { };
  testRejectMissingNestedPlugin = invalid {
    plugins = [
      {
        plugin = a;
        dependPlugins = [ { lazy = null; } ];
      }
    ];
  };
}
