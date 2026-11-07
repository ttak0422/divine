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
