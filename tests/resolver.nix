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
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
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
  conflicts = field: x: y: {
    plugins = [
      ({ plugin = a; } // { ${field} = x; })
      ({ plugin = a; } // { ${field} = y; })
    ];
  };
  checks = {
    empty = (resolve { plugins = [ ]; }).units == [ ];
    packageShorthand = shorthand.nodes.${id a}.package == a;
    contextualPackage =
      builtins.attrNames (resolve { plugins = [ contextual ]; }).nodes == [ (id a) ]
      &&
        builtins.getContext (toString (resolve { plugins = [ contextual ]; }).nodes.${id a}.package)
        == context;
    noInventedTiming = shorthand.unresolvedTiming == [ (id a) ] && shorthand.startupUnits == [ ];
    rootMetadata = shorthand.metadata.metadataExample == "retained";
    detailedSettings =
      detailed.nodes.${id a}.settings == {
        lazy = false;
        config = "setup()";
        preConfig = "prepare()";
        custom.values = [
          1
          "two"
        ];
      };
    optEvenAtStartup = lib.all (node: node.placement == "opt") (builtins.attrValues diamond.nodes);
    nestedAndShared =
      builtins.length (builtins.attrNames diamond.nodes) == 4
      && builtins.length diamond.nodes.${id a}.origins == 2;
    dependencyOrder =
      unitIds diamond == map id [
        a
        b
        c
        d
      ]
      && dependenciesFirst diamond;
    deterministicOrder = unitIds diamond == unitIds reordered;
    startupClosure =
      diamond.startupUnits == map id [
        a
        b
        c
        d
      ]
      && diamond.nodes.${id b}.settings.lazy == true
      && builtins.elem (id a) diamond.unresolvedTiming;
    rootAndRecursiveTools =
      map id diamond.extraPackages == map id [
        toolDeep
        toolDep
        toolGlobal
        toolRoot
      ];
    finiteCycle =
      builtins.length cycle.units == 3
      &&
        cycleUnit.members == map id [
          a
          b
        ]
      && cycleUnit.cyclic
      && dependenciesFirst cycle;
    cycleStartup =
      cycle.startupUnits == map id [
        d
        a
      ];
    cycleTools =
      map id cycle.extraPackages == map id [
        toolDep
        toolRoot
      ];
    selfDependency =
      builtins.length self.units == 1
      && (builtins.head self.units).cyclic
      && (builtins.head self.units).dependencies == [ ];
    repeatedDefinitions =
      builtins.length repeated.nodes.${id a}.origins == 4
      &&
        repeated.nodes.${id a}.dependencies == map id [
          b
          c
        ]
      &&
        repeated.nodes.${id a}.settings == {
          config = "same()";
          preConfig = "before()";
        }
      &&
        map id repeated.extraPackages == map id [
          toolDep
          toolRoot
        ];
    sameNamesDifferentPaths =
      builtins.length (
        builtins.attrNames
          (resolve {
            plugins = [
              a
              (b // { name = a.name; })
            ];
          }).nodes
      ) == 2;
    timingConflict = !(succeeds (resolve (conflicts "lazy" false true)));
    configConflict = !(succeeds (resolve (conflicts "config" "a()" "b()")));
    stringContextConflict =
      !(succeeds (resolve (conflicts "config" "same" (builtins.appendContext "same" context))));
    nestedStringContextConflict =
      !(succeeds (
        resolve (
          conflicts "custom" { values = [ "same" ]; } {
            values = [ (builtins.appendContext "same" context) ];
          }
        )
      ));
    noTriggerConcatenation = !(succeeds (resolve (conflicts "onCommands" [ "A" ] [ "B" ])));
    nestedConflict =
      !(succeeds (resolve {
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
      }));
    conflictNotHiddenByToolQuery = !(succeeds (resolve (conflicts "config" "a()" "b()")).extraPackages);
    invalidRootTools =
      !(succeeds (resolve {
        plugins = [ ];
        extraPackages = false;
      }));
    invalidDependencyTools =
      !(succeeds (resolve {
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
      }));
  };
  failures = builtins.attrNames (lib.filterAttrs (_: value: !value) checks);
in
if failures != [ ] then
  throw "resolver fixture failures: ${lib.concatStringsSep ", " failures}"
else
  {
    passed = true;
    cases = builtins.attrNames checks;
  }
