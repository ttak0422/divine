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
  c = package "c";
  id = package: builtins.unsafeDiscardStringContext (toString package);
  group = "packages:plugins[0]";
  compile = plugins: api.compile { inherit plugins; };
  invalid = plugins: {
    expr = (compile plugins).lua;
    expectedError.type = "ThrownError";
  };
  ordered = compile [
    {
      packages = [
        b
        a
        b
      ];
      config = "shared()";
      preConfig = "prepare()";
    }
  ];
in
{
  testOrderedMembers = {
    expr = ordered.plan.configurations.${group}.members;
    expected = [
      (id b)
      (id a)
    ];
  };
  testSharedHooks = {
    expr =
      ordered.plan.configurations.${group} ? before
      && ordered.plan.configurations.${group} ? after
      && !(ordered.plan.nodes.${id a} ? after);
    expected = true;
  };
  testNoMemberStartupDefault = {
    expr = ordered.plan.startup_units;
    expected = [ group ];
  };
  testLazyMembersStayDeferred = {
    expr =
      (compile [
        {
          packages = [
            a
            b
          ];
          lazy = true;
          onCommands = "Group";
        }
      ]).plan.startup_units;
    expected = [ ];
  };
  testOverlappingIndependentConfigurations = {
    expr =
      let
        result = compile [
          {
            packages = [
              a
              b
            ];
            config = "first()";
            lazy = true;
          }
          {
            packages = [
              b
              c
            ];
            config = "second()";
          }
        ];
      in
      {
        packages = builtins.attrNames result.graph.nodes;
        configurations = builtins.attrNames result.plan.configurations;
        startup = result.plan.startup_units;
      };
    expected = {
      packages = [
        (id a)
        (id b)
        (id c)
      ];
      configurations = [
        group
        "packages:plugins[1]"
      ];
      startup = [ "packages:plugins[1]" ];
    };
  };
  testRecursivePackagesDependencies = {
    expr =
      let
        result = compile [
          {
            packages = [ a ];
            dependPlugins = [
              {
                packages = [
                  b
                  c
                ];
                lazy = true;
              }
            ];
          }
        ];
      in
      (lib.findFirst (unit: unit.id == group) null result.plan.units).dependencies;
    expected = [ "${group}.dependPlugins[0]" ];
  };
  testExplicitDependencyLoadsBeforeGroup = {
    expr =
      let
        result = compile [
          {
            packages = [
              b
              a
            ];
            dependPlugins = [ c ];
          }
        ];
      in
      result.graph.startupUnits;
    expected = [
      (id c)
      group
    ];
  };
  testSingletonSettingsRemainIndependent = {
    expr =
      let
        result = compile [
          {
            packages = [
              a
              b
            ];
            config = "group()";
          }
          {
            plugin = a;
            config = "singleton()";
            lazy = true;
          }
        ];
      in
      result.plan.nodes.${id a}.after.expr != result.plan.configurations.${group}.after.expr;
    expected = true;
  };
  testFiniteCycleContainingGroup = {
    expr =
      let
        result = compile [
          {
            plugin = a;
            dependPlugins = [
              {
                packages = [
                  b
                  c
                ];
                dependPlugins = [ a ];
              }
            ];
          }
        ];
        unit = lib.findFirst (unit: unit.id == id a) null result.graph.units;
      in
      {
        inherit (unit)
          id
          members
          configurations
          cyclic
          ;
        startup = result.graph.startupUnits;
      };
    expected = {
      id = id a;
      members = [
        (id a)
        (id b)
        (id c)
      ];
      configurations = [
        (id a)
        "packages:plugins[0].dependPlugins[0]"
      ];
      cyclic = true;
      startup = [ (id a) ];
    };
  };
  testFiniteCycleDependency = {
    expr =
      let
        result = compile [
          {
            packages = [ c ];
            dependPlugins = [
              {
                plugin = a;
                dependPlugins = [
                  {
                    plugin = b;
                    dependPlugins = [ a ];
                  }
                ];
              }
            ];
          }
        ];
      in
      (lib.findFirst (unit: unit.id == id a) null result.graph.units).cyclic;
    expected = true;
  };
  testSharedAfterPolicy = {
    expr =
      let
        result = compile [
          {
            packages = [
              a
              b
            ];
            loadAfter = true;
          }
          {
            packages = [
              b
              c
            ];
          }
        ];
      in
      result.plan.nodes.${id b}.after_path;
    expected = "${b}/after";
  };
  testConflictingAfterPolicy = invalid [
    {
      packages = [
        a
        b
      ];
      loadAfter = true;
    }
    {
      packages = [
        b
        c
      ];
      loadAfter = false;
    }
  ];
  testRejectBothForms = invalid [
    {
      plugin = a;
      packages = [ a ];
    }
  ];
  testRejectEmptyPackages = invalid [ { packages = [ ]; } ];
  testRejectNonPackageMember = invalid [ { packages = [ { plugin = a; } ]; } ];
  testRejectUnnamedTest = invalid [
    {
      packages = [ a ];
      test = _: a;
    }
  ];
  testNamedChecksOnce = {
    expr =
      builtins.attrNames
        (compile [
          {
            packages = [
              a
              b
            ];
            tests.shared = _: a;
          }
        ]).graph.tests;
    expected = [ "shared" ];
  };
  testNestedTools = {
    expr =
      map id
        (compile [
          {
            packages = [
              a
              b
            ];
            extraPackages = [ c ];
          }
        ]).graph.extraPackages;
    expected = [ (id c) ];
  };
  testGroupDocumentation = {
    expr = lib.hasInfix "Shared documentation" (
      api.mkDocs {
        pkgs.writeText = _: text: text;
        configuration.plugins = [
          {
            packages = [
              a
              b
            ];
            doc = "Shared documentation";
          }
        ];
      }
    );
    expected = true;
  };
  testBuildContextPreserved = {
    expr =
      let
        context = builtins.getContext (builtins.toFile "divine-packages-context" "fixture");
        contextual = a // {
          outPath = builtins.appendContext a.outPath context;
        };
        result = compile [
          {
            packages = [
              contextual
              b
            ];
          }
        ];
      in
      builtins.getContext (toString result.graph.nodes.${id a}.package) == context;
    expected = true;
  };
}
