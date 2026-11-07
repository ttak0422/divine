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
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
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
assert compiled.plan.nodes.${id a}.triggers.commands == [ "Example" ];
assert
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
assert compiled.plan.nodes.${id a}.name != compiled.plan.nodes.${id b}.name;
assert compiled.plan.startup_units == [ (id b) ];
assert lib.hasInfix "function()" compiled.lua;
assert (api.compile { plugins = [ ]; }).plan.units == [ ];
assert !(succeeds (api.compile { plugins = [ a ]; }).lua);
assert !(succeeds (compileOne { unexpected = true; }).lua);
assert !(succeeds (compileOne { config = false; }).lua);
assert !(succeeds (compileOne { onCommands = [ "" ]; }).lua);
assert
  !(succeeds
    (compileOne {
      onKeys = {
        lhs = "x";
        mode = "invalid";
      };
    }).lua
  );
assert
  !(succeeds
    (api.compile {
      plugins = [ ];
      runtimePaths = [ "relative" ];
    }).lua
  );
assert
  !(succeeds
    (api.compile {
      plugins = [ ];
      unknownRoot = true;
    }).lua
  );
assert (compileOne { }).plan.nodes.${id a}.triggers.commands == [ ];
{
  passed = true;
  scope = "provisional Lua plan compilation; no timing defaults adopted";
}
