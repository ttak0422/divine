{
  lib ? import <nixpkgs/lib>,
}:
let
  api = import ../lib { inherit lib; };
  package = name: {
    type = "derivation";
    inherit name;
    outPath = "/nix/store/00000000000000000000000000000000-${name}";
  };
  a = package "a";
  b = package "b";
  c = package "c";
  d = package "d";
  toolRoot = package "tool-root";
  toolDep = package "tool-dependency";
  toolDeep = package "tool-deep";
  toolGlobal = package "tool-global";
  # Context must refer to a real store path: newer Nix validates appendContext inputs.
  context = builtins.getContext (builtins.toFile "divine-context-fixture" "context fixture");
  contextual = a // {
    outPath = builtins.appendContext a.outPath context;
  };
  id = toString;
  resolve = api.resolve;
  unitIds = graph: map (unit: unit.id) graph.units;
  positions =
    graph:
    builtins.listToAttrs (
      lib.imap0 (i: unit: {
        name = unit.id;
        value = i;
      }) graph.units
    );
  dependenciesFirst =
    graph:
    lib.all (
      unit:
      lib.all (
        dependency: (positions graph).${dependency} < (positions graph).${unit.id}
      ) unit.dependencies
    ) graph.units;
  shorthand = resolve {
    plugins = [ a ];
    metadataExample = "retained";
  };
  detailed = resolve {
    plugins = [
      {
        plugin = a;
        lazy = false;
        config = "setup()";
        preConfig = "prepare()";
        custom = {
          values = [
            1
            "two"
          ];
        };
      }
    ];
  };
  diamondRequest = {
    extraPackages = [
      toolGlobal
      toolRoot
    ];
    plugins = [
      {
        plugin = d;
        lazy = false;
        extraPackages = [ toolRoot ];
        dependPlugins = [
          {
            plugin = b;
            lazy = true;
            extraPackages = [ toolDep ];
            dependPlugins = [ a ];
          }
          {
            plugin = c;
            dependPlugins = [
              {
                plugin = a;
                config = "a()";
                extraPackages = [
                  toolDeep
                  toolRoot
                ];
              }
            ];
          }
        ];
      }
    ];
  };
  diamond = resolve diamondRequest;
  reordered = resolve (
    diamondRequest
    // {
      plugins = [
        {
          plugin = d;
          lazy = false;
          extraPackages = [ toolRoot ];
          dependPlugins = lib.reverseList (builtins.head diamondRequest.plugins).dependPlugins;
        }
      ];
    }
  );
  cycle = resolve {
    plugins = [
      {
        plugin = a;
        lazy = false;
        dependPlugins = [ b ];
        extraPackages = [ toolRoot ];
      }
      {
        plugin = b;
        lazy = true;
        dependPlugins = [
          a
          d
        ];
        extraPackages = [
          toolDep
          toolRoot
        ];
      }
      {
        plugin = c;
        lazy = true;
        dependPlugins = [ a ];
      }
      {
        plugin = d;
        lazy = true;
      }
    ];
  };
  cycleUnit = builtins.elemAt cycle.units 1;
  self = resolve {
    plugins = [
      {
        plugin = a;
        lazy = false;
        dependPlugins = [ a ];
      }
    ];
  };
  repeated = resolve {
    plugins = [
      a
      {
        plugin = a;
        config = "same()";
        dependPlugins = [ b ];
        extraPackages = [ toolRoot ];
      }
      {
        plugin = a;
        preConfig = "before()";
        dependPlugins = [
          c
          b
        ];
        extraPackages = [ toolDep ];
      }
      {
        plugin = a;
        config = "same()";
      }
    ];
  };
  packaged = a // {
    dependencies = [ c ];
    nativeBuildInputs = [ toolRoot ];
    buildInputs = [ toolDep ];
    propagatedBuildInputs = [ toolDeep ];
  };
  packagedGraph = resolve {
    plugins = [
      {
        plugin = packaged;
        lazy = false;
        dependPlugins = [
          {
            plugin = b;
            lazy = true;
          }
        ];
        extraPackages = [ toolGlobal ];
      }
    ];
  };
  conflicts = field: x: y: {
    plugins = [
      ({ plugin = a; } // { ${field} = x; })
      ({ plugin = a; } // { ${field} = y; })
    ];
  };
in
{
  testIgnorePackagePluginDependencies = {
    expr =
      builtins.attrNames packagedGraph.nodes == map id [
        a
        b
      ]
      && packagedGraph.nodes.${id a}.dependencies == [ (id b) ];
    expected = true;
  };
  testPreservePackageBuildInputs = {
    expr =
      let
        retained = packagedGraph.nodes.${id a}.package;
      in
      retained.dependencies == [ c ]
      && retained.nativeBuildInputs == [ toolRoot ]
      && retained.buildInputs == [ toolDep ]
      && retained.propagatedBuildInputs == [ toolDeep ]
      && packagedGraph.extraPackages == [ toolGlobal ];
    expected = true;
  };
  testDoNotEvaluatePackagePluginDependencies = {
    expr =
      builtins.attrNames
        (resolve {
          plugins = [
            {
              plugin = a // {
                dependencies = throw "root metadata must not be evaluated";
              };
              dependPlugins = [ (b // { dependencies = throw "nested metadata must not be evaluated"; }) ];
            }
          ];
        }).nodes == map id [
        a
        b
      ];
    expected = true;
  };
  testEmpty = {
    expr = (resolve { plugins = [ ]; }).units == [ ];
    expected = true;
  };
  testPackageShorthand = {
    expr = shorthand.nodes.${id a}.package == a;
    expected = true;
  };
  testContextualPackage = {
    expr =
      builtins.attrNames (resolve { plugins = [ contextual ]; }).nodes == [ (id a) ]
      &&
        builtins.getContext (toString (resolve { plugins = [ contextual ]; }).nodes.${id a}.package)
        == context;
    expected = true;
  };
  testDefaultStartupTiming = {
    expr = shorthand.nodes.${id a}.settings.lazy == false && shorthand.startupUnits == [ (id a) ];
    expected = true;
  };
  testRootMetadata = {
    expr = shorthand.metadata.metadataExample == "retained";
    expected = true;
  };
  testDetailedSettings = {
    expr =
      detailed.nodes.${id a}.settings == {
        lazy = false;
        config = "setup()";
        preConfig = "prepare()";
        custom.values = [
          1
          "two"
        ];
      };
    expected = true;
  };
  testOptEvenAtStartup = {
    expr = lib.all (node: node.placement == "opt") (builtins.attrValues diamond.nodes);
    expected = true;
  };
  testNestedAndShared = {
    expr =
      builtins.length (builtins.attrNames diamond.nodes) == 4
      && builtins.length diamond.nodes.${id a}.origins == 2;
    expected = true;
  };
  testDependencyOrder = {
    expr =
      unitIds diamond == map id [
        a
        b
        c
        d
      ]
      && dependenciesFirst diamond;
    expected = true;
  };
  testDeterministicOrder = {
    expr = unitIds diamond == unitIds reordered;
    expected = true;
  };
  testStartupClosure = {
    expr =
      diamond.startupUnits == map id [
        a
        b
        c
        d
      ]
      && diamond.nodes.${id b}.settings.lazy == true
      && diamond.nodes.${id a}.settings.lazy == false;
    expected = true;
  };
  testRootAndRecursiveTools = {
    expr =
      map id diamond.extraPackages == map id [
        toolDeep
        toolDep
        toolGlobal
        toolRoot
      ];
    expected = true;
  };
  testFiniteCycle = {
    expr =
      builtins.length cycle.units == 3
      &&
        cycleUnit.members == map id [
          a
          b
        ]
      && cycleUnit.cyclic
      && dependenciesFirst cycle;
    expected = true;
  };
  testCycleStartup = {
    expr =
      cycle.startupUnits == map id [
        d
        a
      ];
    expected = true;
  };
  testCycleTools = {
    expr =
      map id cycle.extraPackages == map id [
        toolDep
        toolRoot
      ];
    expected = true;
  };
  testSelfDependency = {
    expr =
      builtins.length self.units == 1
      && (builtins.head self.units).cyclic
      && (builtins.head self.units).dependencies == [ ];
    expected = true;
  };
  testRepeatedDefinitions = {
    expr =
      builtins.length repeated.nodes.${id a}.origins == 4
      &&
        repeated.nodes.${id a}.dependencies == map id [
          b
          c
        ]
      &&
        repeated.nodes.${id a}.settings == {
          lazy = false;
          config = "same()";
          preConfig = "before()";
        }
      &&
        map id repeated.extraPackages == map id [
          toolDep
          toolRoot
        ];
    expected = true;
  };
  testSameNamesDifferentPaths = {
    expr =
      builtins.length (
        builtins.attrNames
          (resolve {
            plugins = [
              a
              (b // { name = a.name; })
            ];
          }).nodes
      ) == 2;
    expected = true;
  };
  testTimingConflict = {
    expr = builtins.deepSeq ((resolve (conflicts "lazy" false true))) true;
    expectedError.type = "ThrownError";
  };
  testConfigConflict = {
    expr = builtins.deepSeq ((resolve (conflicts "config" "a()" "b()"))) true;
    expectedError.type = "ThrownError";
  };
  testStringContextConflict = {
    expr = builtins.deepSeq (
      (resolve (conflicts "config" "same" (builtins.appendContext "same" context)))
    ) true;
    expectedError.type = "ThrownError";
  };
  testNestedStringContextConflict = {
    expr = builtins.deepSeq (
      (resolve (
        conflicts "custom" { values = [ "same" ]; } {
          values = [ (builtins.appendContext "same" context) ];
        }
      ))
    ) true;
    expectedError.type = "ThrownError";
  };
  testNoTriggerConcatenation = {
    expr = builtins.deepSeq ((resolve (conflicts "onCommands" [ "A" ] [ "B" ]))) true;
    expectedError.type = "ThrownError";
  };
  testNestedConflict = {
    expr = builtins.deepSeq (
      (resolve {
        plugins = [
          {
            plugin = a;
            dependPlugins = [
              {
                plugin = b;
                config = "one()";
              }
            ];
          }
          {
            plugin = b;
            config = "two()";
          }
        ];
      })
    ) true;
    expectedError.type = "ThrownError";
  };
  testConflictNotHiddenByToolQuery = {
    expr = builtins.deepSeq ((resolve (conflicts "config" "a()" "b()")).extraPackages) true;
    expectedError.type = "ThrownError";
  };
  testInvalidRootTools = {
    expr = builtins.deepSeq (
      (resolve {
        plugins = [ ];
        extraPackages = false;
      })
    ) true;
    expectedError.type = "ThrownError";
  };
  testInvalidDependencyTools = {
    expr = builtins.deepSeq (
      (resolve {
        plugins = [
          {
            plugin = a;
            dependPlugins = [
              {
                plugin = b;
                extraPackages = [ "not-a-package" ];
              }
            ];
          }
        ];
      })
    ) true;
    expectedError.type = "ThrownError";
  };
}
