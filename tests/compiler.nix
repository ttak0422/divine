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
  testRejectMissingTiming = {
    expr = builtins.deepSeq ((api.compile { plugins = [ a ]; }).lua) true;
    expectedError.type = "ThrownError";
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
