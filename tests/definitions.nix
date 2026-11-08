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
  check = { pkgs }: pkgs.result;
  checks =
    plugins:
    api.mkChecks {
      pkgs.result = a;
      configuration = { inherit plugins; };
      bundle = throw "package-only checks must not evaluate bundle";
      neovim = throw "package-only checks must not evaluate neovim";
    };
  invalid = plugins: {
    expr = builtins.attrNames (api.resolve { inherit plugins; }).tests;
    expectedError.type = "ThrownError";
  };
in
{
  testNamedPackageCheck = {
    expr =
      (checks [
        {
          plugin = a;
          tests.package = check;
        }
      ]).package.outPath;
    expected = a.outPath;
  };
  testOptionalContext = {
    expr =
      (checks [
        {
          plugin = a;
          tests.package =
            {
              pkgs,
              other ? true,
            }:
            assert other;
            pkgs.result;
        }
      ]).package.outPath;
    expected = a.outPath;
  };
  testSuppliedContext = {
    expr =
      (api.mkChecks {
        pkgs = { };
        bundle = a;
        neovim = b;
        configuration.plugins = [
          {
            plugin = a;
            tests.context =
              { bundle, neovim }:
              assert bundle.outPath == a.outPath;
              neovim;
          }
        ];
      }).context.outPath;
    expected = b.outPath;
  };
  testModuleDiscriminatorAsName = {
    expr =
      (checks [
        {
          plugin = a;
          tests._type = check;
        }
      ])._type.outPath;
    expected = a.outPath;
  };
  testEmptyChecks = {
    expr = builtins.attrNames (checks [ a ]);
    expected = [ ];
  };
  testNestedCollection = {
    expr = builtins.attrNames (checks [
      {
        plugin = a;
        tests.outer = check;
        dependPlugins = [
          {
            plugin = b;
            tests.inner = check;
          }
        ];
      }
    ]);
    expected = [
      "inner"
      "outer"
    ];
  };
  testDisjointRepeatedTests = {
    expr = builtins.attrNames (checks [
      {
        plugin = a;
        tests.first = check;
      }
      {
        plugin = a;
        tests.second = check;
      }
    ]);
    expected = [
      "first"
      "second"
    ];
  };
  testDuplicateSameFunction = invalid [
    {
      plugin = a;
      tests.same = check;
    }
    {
      plugin = a;
      tests.same = check;
    }
  ];
  testDuplicateDifferentFunctions = invalid [
    {
      plugin = a;
      tests.same = check;
    }
    {
      plugin = a;
      tests.same = _: b;
    }
  ];
  testDuplicateAcrossPackages = invalid [
    {
      plugin = a;
      tests.same = check;
    }
    {
      plugin = b;
      tests.same = check;
    }
  ];
  testDuplicateNested = invalid [
    {
      plugin = a;
      tests.same = check;
      dependPlugins = [
        {
          plugin = b;
          tests.same = check;
        }
      ];
    }
  ];
  testRejectNonFunction = invalid [
    {
      plugin = a;
      tests.bad = a;
    }
  ];
  testRejectNonSet = invalid [
    {
      plugin = a;
      tests = check;
    }
  ];
  testRejectEmptyName = invalid [
    {
      plugin = a;
      tests."" = check;
    }
  ];
  testRejectNonDerivation = {
    expr =
      (checks [
        {
          plugin = a;
          tests.bad = _: "not a check";
        }
      ]).bad;
    expectedError.type = "ThrownError";
  };
  testRuntimeDoesNotRunChecks = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            doc = "Only documentation";
            tests.broken = _: throw "not invoked";
          }
        ];
      }).lua == (api.compile { plugins = [ a ]; }).lua;
    expected = true;
  };
  testShorthandDoesNotRepeatTests = {
    expr = builtins.attrNames (checks [
      {
        plugin = a;
        tests.once = check;
      }
      {
        plugin = b;
        dependPlugins = [ a ];
      }
    ]);
    expected = [ "once" ];
  };
  testFiniteCrossFileCycle = {
    expr =
      let
        groups = {
          first = {
            plugin = a;
            dependPlugins = [ groups.second.plugin ];
            tests.first = check;
          };
          second = {
            plugin = b;
            dependPlugins = [ groups.first.plugin ];
            tests.second = check;
          };
        };
        result = api.compile { plugins = builtins.attrValues groups; };
      in
      builtins.deepSeq result.lua {
        tests = builtins.attrNames result.graph.tests;
        cyclic = (builtins.head result.graph.units).cyclic;
      };
    expected = {
      tests = [
        "first"
        "second"
      ];
      cyclic = true;
    };
  };
  testRepeatedDocs = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            doc = "Same";
          }
          {
            plugin = a;
            doc = "Same";
          }
        ];
      }).graph.nodes.${a.outPath}.settings.doc;
    expected = "Same";
  };
  testConflictingDocs = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            doc = "First";
          }
          {
            plugin = a;
            doc = "Second";
          }
        ];
      }).lua;
    expectedError.type = "ThrownError";
  };
  testRejectNonStringDoc = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            doc = 123;
          }
        ];
      }).lua;
    expectedError.type = "ThrownError";
  };
  testRejectRootTestRegistry = {
    expr =
      (api.compile {
        plugins = [ a ];
        tests.bad = check;
      }).lua;
    expectedError.type = "ThrownError";
  };
  testCheckValuesRemainLazy = {
    expr =
      (checks [
        {
          plugin = a;
          tests = {
            selected = check;
            unselected = _: throw "not selected";
          };
        }
      ]).selected.outPath;
    expected = a.outPath;
  };
  testDocsDoNotRunChecks = {
    expr = api.mkDocs {
      pkgs.writeText = _: text: text;
      configuration.plugins = [
        {
          plugin = a;
          doc = "Inline prose";
          tests.broken = _: throw "not invoked";
        }
      ];
    };
    expected = "# Configuration\n\n## a\n\nPackage: `${a.outPath}`\n\nDeclarations: `plugins[0]`\n\nInline prose\n";
  };
  testDuplicateNotHiddenByToolQuery = {
    expr =
      (api.resolve {
        plugins = [
          {
            plugin = a;
            tests.same = check;
          }
          {
            plugin = a;
            tests.same = check;
          }
        ];
      }).extraPackages;
    expectedError.type = "ThrownError";
  };
  testSingletonPackageCheck = {
    expr =
      (checks [
        {
          plugin = a;
          test = check;
        }
      ]).a.outPath;
    expected = a.outPath;
  };
  testSingletonPackageName = {
    expr = builtins.attrNames (checks [
      {
        plugin = a // {
          name = "example-1.2.3";
        };
        test = check;
      }
    ]);
    expected = [ "example" ];
  };
  testNestedSingleton = {
    expr = builtins.attrNames (checks [
      {
        plugin = a;
        dependPlugins = [
          {
            plugin = b;
            test = check;
          }
        ];
      }
    ]);
    expected = [ "b" ];
  };
  testDuplicateSingleton = invalid [
    {
      plugin = a;
      test = check;
    }
    {
      plugin = a;
      test = check;
    }
  ];
  testSingletonNamedCollision = invalid [
    {
      plugin = a;
      test = check;
    }
    {
      plugin = b;
      tests.a = check;
    }
  ];
  testNamedSingletonCollision = invalid [
    {
      plugin = b;
      tests.a = check;
    }
    {
      plugin = a;
      test = check;
    }
  ];
  testBothForms = invalid [
    {
      plugin = a;
      test = check;
      tests.named = check;
    }
  ];
  testBothFormsEmptyPlural = invalid [
    {
      plugin = a;
      test = check;
      tests = { };
    }
  ];
  testRejectSingletonMap = invalid [
    {
      plugin = a;
      test.named = check;
    }
  ];
  testRejectSingletonDerivation = invalid [
    {
      plugin = a;
      test = b;
    }
  ];
  testSingletonValuesRemainLazy = {
    expr =
      (checks [
        {
          plugin = a;
          test = check;
        }
        {
          plugin = b;
          test = _: throw "not selected";
        }
      ]).a.outPath;
    expected = a.outPath;
  };
  testRuntimeDoesNotRunSingleton = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            test = _: throw "not invoked";
          }
        ];
      }).lua == (api.compile { plugins = [ a ]; }).lua;
    expected = true;
  };
  testSingletonNonDerivation = {
    expr =
      (checks [
        {
          plugin = a;
          test = _: "not a derivation";
        }
      ]).a;
    expectedError.type = "ThrownError";
  };
  testCompileRejectBothForms = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            test = check;
            tests = { };
          }
        ];
      }).lua;
    expectedError.type = "ThrownError";
  };
  testCompileRejectSingletonMap = {
    expr =
      (api.compile {
        plugins = [
          {
            plugin = a;
            test.named = check;
          }
        ];
      }).lua;
    expectedError.type = "ThrownError";
  };
  testRejectRootSingleton = {
    expr =
      (api.compile {
        plugins = [ a ];
        test = check;
      }).lua;
    expectedError.type = "ThrownError";
  };
}
