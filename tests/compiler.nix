{ lib }:
let
  api = import ../lib { inherit lib; };
  package = name: {
    type = "derivation";
    inherit name;
    outPath = "/nix/store/00000000000000000000000000000000-${name}";
  };
  a = package "a";
  b = package "b";
  id = p: toString p;
  compiled = api.compile {
    plugins = [
      {
        plugin = a;
        lazy = true;
        onCommands = "Example";
        onKeys = [
          "<leader>x"
          {
            lhs = "<F3>";
            mode = "i";
          }
        ];
        onModules = [ "example" ];
        dependPlugins = [
          {
            plugin = b;
            lazy = false;
          }
        ];
        preConfig = "vim.g.before = true";
        config = "vim.g.after = true";
      }
    ];
    startupConfig = "vim.g.mapleader = ' '";
  };
  compileOne =
    settings:
    api.compile {
      plugins = [
        (
          {
            plugin = a;
            lazy = true;
          }
          // settings
        )
      ];
    };
in
{
  testAfterOptIn = {
    expr = (compileOne { loadAfter = true; }).plan.nodes.${id a}.after_path;
    expected = "${a}/after";
  };
  testAfterDefaultAndFalse = {
    expr = lib.all (settings: !((compileOne settings).plan.nodes.${id a} ? after_path)) [
      { }
      { loadAfter = false; }
    ];
    expected = true;
  };
  testAfterRepeatedAndNested = {
    expr =
      (api.compile {
        plugins = [
          a
          {
            plugin = b;
            dependPlugins = [
              {
                plugin = a;
                loadAfter = true;
              }
            ];
          }
        ];
      }).plan.nodes.${id a}.after_path;
    expected = "${a}/after";
  };
  testAfterConflict = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            loadAfter = true;
          }
          {
            plugin = a;
            loadAfter = false;
          }
        ];
      }).lua;
    expectedError.type = "ThrownError";
  };
  testRejectInvalidAfter = {
    expr = (compileOne { loadAfter = "plugin"; }).lua;
    expectedError.type = "ThrownError";
  };
  testNormalizeEventAliases = {
    expr =
      (compileOne {
        onEvents = [
          "bufread"
          "BUFREADPOST"
          "BufCreate"
          "bufadd"
          "BufWrite"
          "BUFWRITEPRE"
          "FileEncoding"
          "encodingchanged"
          "uSeR"
        ];
      }).plan.nodes.${id a}.triggers.events;
    expected = [
      "BufReadPost"
      "BufAdd"
      "BufWritePre"
      "EncodingChanged"
      "User"
    ];
  };
  testNormalizeEveryEventCase = {
    expr =
      let
        names = (import ../lib/events.nix).names;
      in
      (compileOne { onEvents = map lib.toUpper names ++ map lib.toLower names; })
      .plan.nodes.${id a}.triggers.events == names;
    expected = true;
  };
  testRejectUnknownEvent = {
    expr = (compileOne { onEvents = "NotAnEvent"; }).lua;
    expectedError = {
      type = "ThrownError";
      msg = "divine compiler: unknown onEvents event 'NotAnEvent'.*";
    };
  };
  testGeneratedPlanInvariants = {
    expr =
      let
        c = package "c";
        d = package "d";
        plan =
          (api.compile {
            plugins = [
              {
                plugin = a;
                dependPlugins = [
                  b
                  c
                ];
                preConfig = "local ready = true";
                load = "vim.cmd.packadd(name)";
                config = "local done = true";
              }
              {
                plugin = b;
                dependPlugins = [
                  a
                  d
                ];
              }
              {
                plugin = c;
                dependPlugins = [ d ];
              }
              {
                plugin = d;
                dependPlugins = [ d ];
                lazy = true;
              }
            ];
            startupConfig = "vim.g.ready = true";
          }).plan;
        nodeIds = builtins.attrNames plan.nodes;
        unitIds = map (unit: unit.id) plan.units;
        members = lib.concatMap (unit: unit.members) plan.units;
        names = map (node: node.name) (builtins.attrValues plan.nodes);
        ordered =
          builtins.foldl'
            (state: unit: {
              seen = state.seen ++ [ unit.id ];
              valid =
                state.valid
                && builtins.isString unit.id
                && builtins.isList unit.members
                && unit.members != [ ]
                && builtins.isList unit.dependencies
                && lib.all (dependency: builtins.elem dependency state.seen) unit.dependencies;
            })
            {
              seen = [ ];
              valid = true;
            }
            plan.units;
        callback = value: value._type == "lua-inline" && lib.hasPrefix "function(" value.expr;
      in
      builtins.isAttrs plan.nodes
      && builtins.isList plan.units
      && builtins.length unitIds == builtins.length (lib.unique unitIds)
      && builtins.sort builtins.lessThan members == nodeIds
      && builtins.length names == builtins.length (lib.unique names)
      && lib.all (name: builtins.match "divine-[0-9a-f]{64}" name != null) names
      && ordered.valid
      && builtins.isList plan.startup_units
      && lib.all (unit: builtins.elem unit unitIds) plan.startup_units
      && callback plan.startup
      && lib.all (hook: callback plan.nodes.${id a}.${hook}) [
        "before"
        "load"
        "after"
      ];
    expected = true;
  };
  testRejectInvalidPreConfig = {
    expr = builtins.deepSeq ((compileOne { preConfig = false; }).lua) true;
    expectedError.type = "ThrownError";
  };
  testRejectInvalidLoad = {
    expr = builtins.deepSeq ((compileOne { load = false; }).lua) true;
    expectedError.type = "ThrownError";
  };
  testRejectInvalidStartupConfig = {
    expr = builtins.deepSeq ((api.compile {
      plugins = [ ];
      startupConfig = false;
    }).lua
    ) true;
    expectedError.type = "ThrownError";
  };
  testNormalizeCommandTrigger = {
    expr = compiled.plan.nodes.${id a}.triggers.commands == [ "Example" ];
    expected = true;
  };
  testNormalizeKeyTriggers = {
    expr =
      compiled.plan.nodes.${id a}.triggers.keys == [
        {
          lhs = "<leader>x";
          mode = "n";
        }
        {
          lhs = "<F3>";
          mode = "i";
        }
      ];
    expected = true;
  };
  testUniquePluginNames = {
    expr = compiled.plan.nodes.${id a}.name != compiled.plan.nodes.${id b}.name;
    expected = true;
  };
  testDependencyStartupUnit = {
    expr = compiled.plan.startup_units == [ (id b) ];
    expected = true;
  };
  testEmitLuaCallbacks = {
    expr = lib.hasInfix "function()" compiled.lua;
    expected = true;
  };
  testEmptyPlan = {
    expr = (api.compile { plugins = [ ]; }).plan.units == [ ];
    expected = true;
  };
  testDefaultStartupShorthand = {
    expr =
      let
        result = api.compile { plugins = [ a ]; };
      in
      builtins.deepSeq result.lua (
        !result.graph.nodes.${id a}.settings.lazy && result.plan.startup_units == [ (id a) ]
      );
    expected = true;
  };
  testDefaultStartupDetailedAndNested = {
    expr =
      let
        result = api.compile {
          plugins = [
            {
              plugin = a;
              onCommands = "Example";
              dependPlugins = [ { plugin = b; } ];
            }
          ];
        };
      in
      builtins.deepSeq result.lua (
        !result.graph.nodes.${id a}.settings.lazy
        && !result.graph.nodes.${id b}.settings.lazy
        &&
          result.plan.startup_units == [
            (id b)
            (id a)
          ]
        && result.plan.nodes.${id a}.triggers.commands == [ "Example" ]
      );
    expected = true;
  };
  testExplicitStartupOverridesOmission = {
    expr =
      let
        definitions = [
          a
          {
            plugin = a;
            lazy = false;
            dependPlugins = [ b ];
          }
        ];
        result = api.compile { plugins = definitions; };
        reversed = api.compile { plugins = lib.reverseList definitions; };
      in
      builtins.deepSeq [ result.lua reversed.lua ] (
        !result.graph.nodes.${id a}.settings.lazy
        && !result.graph.nodes.${id b}.settings.lazy
        &&
          result.plan.startup_units == [
            (id b)
            (id a)
          ]
        && reversed.plan == result.plan
      );
    expected = true;
  };
  testExplicitDeferredOverridesOmission = {
    expr =
      let
        definitions = [
          a
          {
            plugin = a;
            lazy = true;
            onEvents = "BufEnter";
            dependPlugins = [ b ];
          }
        ];
        result = api.compile { plugins = definitions; };
        reversed = api.compile { plugins = lib.reverseList definitions; };
      in
      builtins.deepSeq [ result.lua reversed.lua ] (
        result.graph.nodes.${id a}.settings.lazy
        && !result.graph.nodes.${id b}.settings.lazy
        && result.plan.startup_units == [ (id b) ]
        && result.plan.nodes.${id a}.triggers.events == [ "BufEnter" ]
        && reversed.plan == result.plan
      );
    expected = true;
  };
  testRejectUnknownSettings = {
    expr = builtins.deepSeq ((compileOne { unexpected = true; }).lua) true;
    expectedError.type = "ThrownError";
  };
  testRejectInvalidConfig = {
    expr = builtins.deepSeq ((compileOne { config = false; }).lua) true;
    expectedError.type = "ThrownError";
  };
  testRejectEmptyCommand = {
    expr = builtins.deepSeq ((compileOne { onCommands = [ "" ]; }).lua) true;
    expectedError.type = "ThrownError";
  };
  testRejectInvalidKeyMode = {
    expr = builtins.deepSeq ((compileOne {
      onKeys = {
        lhs = "x";
        mode = "invalid";
      };
    }).lua
    ) true;
    expectedError.type = "ThrownError";
  };
  testAcceptOperatorPendingKeyMode = {
    expr = builtins.deepSeq ((compileOne {
      onKeys = {
        lhs = "x";
        mode = "o";
      };
    }).lua
    ) true;
    expected = true;
  };
  testRejectRelativeRuntimePath = {
    expr = builtins.deepSeq ((api.compile {
      plugins = [ ];
      runtimePaths = [ "relative" ];
    }).lua
    ) true;
    expectedError.type = "ThrownError";
  };
  testRejectUnknownRootSettings = {
    expr = builtins.deepSeq ((api.compile {
      plugins = [ ];
      unknownRoot = true;
    }).lua
    ) true;
    expectedError.type = "ThrownError";
  };
  testTriggerlessDeferredPlan = {
    expr = (compileOne { }).plan.nodes.${id a}.triggers.commands == [ ];
    expected = true;
  };
}
