{ lib }:
let
  api = import ../lib { inherit lib; };
  a = {
    type = "derivation";
    name = "a";
    outPath = "/nix/store/00000000000000000000000000000000-a";
  };
  b = a // {
    name = "b";
    outPath = "/nix/store/00000000000000000000000000000000-b";
  };
  id = a.outPath;
  context = builtins.getContext (builtins.toFile "divine-trigger-context" "fixture");
  contextual = value: builtins.appendContext value context;
  definitions =
    field: values:
    map (value: {
      plugin = a;
      ${field} = value;
    }) values;
  compile = field: values: api.compile { plugins = definitions field values; };
  rejected =
    field: values: !(builtins.tryEval (builtins.deepSeq (compile field values).lua true)).success;
  equivalent = field: kind: values: expected: {
    expr =
      lib.all
        (
          declarations:
          let
            request.plugins = definitions field declarations;
            graph = api.resolve request;
            compiled = api.compile request;
          in
          builtins.length graph.nodes.${id}.origins == builtins.length values
          && compiled.plan.nodes.${id}.triggers.${kind} == expected
        )
        [
          values
          (lib.reverseList values)
        ];
    expected = true;
  };
  fields = [
    "onEvents"
    "onCommands"
    "onFiletypes"
    "onModules"
  ];
  condition = field: if field == "onEvents" then "BufReadPost" else "Example";
in
{
  testCommandSingletonList =
    equivalent "onCommands" "commands"
      [
        "Example"
        [ "Example" ]
      ]
      [ "Example" ];
  testFiletypeSingletonList =
    equivalent "onFiletypes" "filetypes"
      [
        "lua"
        [ "lua" ]
      ]
      [ "lua" ];
  testModuleSingletonList =
    equivalent "onModules" "modules"
      [
        "example"
        [ "example" ]
      ]
      [ "example" ];
  testEventCanonicalForms =
    equivalent "onEvents" "events"
      [
        "bufread"
        [
          "BufReadPost"
          "BUFREAD"
        ]
      ]
      [ "BufReadPost" ];
  testEveryEventAliasAndCase = {
    expr = lib.all (
      alias:
      let
        canonical = (import ../lib/events.nix).aliases.${alias};
        result = compile "onEvents" [
          alias
          [
            canonical
            (lib.toLower alias)
          ]
        ];
      in
      result.plan.nodes.${id}.triggers.events == [ canonical ]
    ) (builtins.attrNames (import ../lib/events.nix).aliases);
    expected = true;
  };
  testKeyCanonicalForms =
    equivalent "onKeys" "keys"
      [
        "x"
        [ "x" ]
        { lhs = "x"; }
        [
          {
            lhs = "x";
            mode = "n";
          }
        ]
      ]
      [
        {
          lhs = "x";
          mode = "n";
        }
      ];
  testConditionDuplicatesPreserveFirstOrder =
    equivalent "onCommands" "commands"
      [
        [
          "Second"
          "First"
          "Second"
        ]
        [
          "Second"
          "First"
        ]
      ]
      [ "Second" "First" ];
  testNestedRepetitions = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            onEvents = "bufread";
          }
          {
            plugin = b;
            dependPlugins = [
              {
                plugin = a;
                onEvents = [ "BufReadPost" ];
              }
            ];
          }
        ];
      }).plan.nodes.${id}.triggers.events;
    expected = [ "BufReadPost" ];
  };
  testRetainRawSettingsAndOrigins = {
    expr =
      let
        graph = api.resolve {
          plugins = definitions "onCommands" [
            "Example"
            [ "Example" ]
          ];
        };
      in
      {
        value = graph.nodes.${id}.settings.onCommands;
        origins = graph.nodes.${id}.origins;
      };
    expected = {
      value = "Example";
      origins = [
        "plugins[0]"
        "plugins[1]"
      ];
    };
  };
  testOmissionDoesNotSupplyEmptyDefaults = {
    expr =
      (api.compile {
        plugins = [
          a
          {
            plugin = a;
            onCommands = "Example";
          }
        ];
      }).plan.nodes.${id}.triggers.commands;
    expected = [ "Example" ];
  };
  testExplicitEmptyStillConflicts = {
    expr = lib.all (
      field:
      rejected field [
        [ ]
        (condition field)
      ]
    ) fields;
    expected = true;
  };
  testOrderedConditionsStillConflict = {
    expr = lib.all (
      field:
      let
        first = condition field;
        second = if field == "onEvents" then "BufEnter" else "Other";
      in
      rejected field [
        [
          first
          second
        ]
        [
          second
          first
        ]
      ]
    ) fields;
    expected = true;
  };
  testDifferentConditionsStillConflict = {
    expr = lib.all (
      field:
      rejected field [
        (condition field)
        [ (if field == "onEvents" then "BufEnter" else "Other") ]
      ]
    ) fields;
    expected = true;
  };
  testNonEventCaseStillConflicts = {
    expr =
      lib.all
        (
          field:
          rejected field [
            "Example"
            [ "example" ]
          ]
        )
        [
          "onCommands"
          "onFiletypes"
          "onModules"
        ];
    expected = true;
  };
  testKeyOrderModeAndLhsStillConflict = {
    expr =
      rejected "onKeys" [
        [
          "x"
          "y"
        ]
        [
          "y"
          "x"
        ]
      ]
      && rejected "onKeys" [
        "x"
        {
          lhs = "x";
          mode = "i";
        }
      ]
      && rejected "onKeys" [
        "x"
        { lhs = "y"; }
      ];
    expected = true;
  };
  testDuplicateKeysAreNotEquivalent = {
    expr = rejected "onKeys" [
      "x"
      [
        "x"
        "x"
      ]
    ];
    expected = true;
  };
  testDuplicateKeysRemainInPlan = {
    expr =
      (compile "onKeys" [
        [
          "x"
          "x"
        ]
      ]).plan.nodes.${id}.triggers.keys;
    expected = [
      {
        lhs = "x";
        mode = "n";
      }
      {
        lhs = "x";
        mode = "n";
      }
    ];
  };
  testStringContextsStillConflict = {
    expr = lib.all (
      field:
      rejected field [
        (contextual (condition field))
        [ (condition field) ]
      ]
    ) fields;
    expected = true;
  };
  testMatchingContextsAreAccepted = {
    expr = lib.all (
      field:
      let
        text = contextual (condition field);
        result = compile field [
          text
          [ text ]
        ];
      in
      builtins.deepSeq result.lua (
        builtins.getContext result.graph.nodes.${id}.settings.${field} == context
      )
    ) fields;
    expected = true;
  };
  testEventAliasContextsStillConflict = {
    expr = rejected "onEvents" [
      (contextual "bufread")
      [ "BufReadPost" ]
    ];
    expected = true;
  };
  testCanonicalEventRetainsContextInPlan = {
    expr =
      let
        result = compile "onEvents" [
          (contextual "bufread")
          [ (contextual "BufReadPost") ]
        ];
        event = builtins.head result.plan.nodes.${id}.triggers.events;
      in
      event == "BufReadPost" && builtins.getContext event == context;
    expected = true;
  };
  testMatchingKeyContextsAreAccepted =
    equivalent "onKeys" "keys"
      [
        (contextual "x")
        [ { lhs = contextual "x"; } ]
      ]
      [
        {
          lhs = contextual "x";
          mode = "n";
        }
      ];
  testMixedContextDuplicatesAreNotCollapsed = {
    expr = lib.all (
      field:
      let
        text = condition field;
      in
      rejected field [
        [
          text
          (contextual text)
        ]
        [ text ]
      ]
    ) fields;
    expected = true;
  };
  testKeyContextsStillConflict = {
    expr =
      rejected "onKeys" [
        (contextual "x")
        [
          {
            lhs = "x";
            mode = "n";
          }
        ]
      ]
      && rejected "onKeys" [
        "x"
        {
          lhs = "x";
          mode = contextual "n";
        }
      ];
    expected = true;
  };
  testInvalidRawValuesKeepStrictComparison = {
    expr =
      let
        graph = api.resolve {
          plugins = definitions "onCommands" [
            [ false ]
            [ false ]
          ];
        };
      in
      graph.nodes.${id}.settings.onCommands == [ false ]
      && rejected "onCommands" [
        [ false ]
        [ false ]
      ];
    expected = true;
  };
  testUnknownRawEventsRemainCompilerErrors = {
    expr =
      let
        graph = api.resolve {
          plugins = definitions "onEvents" [
            "UnknownEvent"
            "UnknownEvent"
          ];
        };
      in
      graph.nodes.${id}.settings.onEvents == "UnknownEvent"
      && rejected "onEvents" [
        "UnknownEvent"
        "UnknownEvent"
      ];
    expected = true;
  };
  testInvalidRawFormsDoNotBecomeEquivalent = {
    expr =
      !(builtins.tryEval (
        builtins.deepSeq (api.resolve {
          plugins = definitions "onEvents" [
            "UnknownEvent"
            [ "UnknownEvent" ]
          ];
        }) true
      )).success;
    expected = true;
  };
  testIndependentGroupsDoNotMerge = {
    expr = builtins.length (
      builtins.attrNames
        (api.compile {
          plugins = [
            {
              packages = [ a ];
              onCommands = "One";
            }
            {
              packages = [ a ];
              onCommands = "Two";
            }
          ];
        }).graph.configurationNodes
    );
    expected = 2;
  };
  testConflictRetainsBothLocations = {
    expr =
      (compile "onCommands" [
        "First"
        [ "Second" ]
      ]).lua;
    expectedError = {
      type = "ThrownError";
      msg = "divine resolver: conflicting field 'onCommands'.*plugins\\[0\\].*plugins\\[1\\]";
    };
  };
}
