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
  checks = plugins: api.mkChecks {
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
    expr = (checks [ { plugin = a; test.package = check; } ]).package.outPath;
    expected = a.outPath;
  };
  testOptionalContext = {
    expr = (checks [ {
      plugin = a;
      test.package = { pkgs, other ? true }: assert other; pkgs.result;
    } ]).package.outPath;
    expected = a.outPath;
  };
  testSuppliedContext = {
    expr = (api.mkChecks {
      pkgs = { };
      bundle = a;
      neovim = b;
      configuration.plugins = [ {
        plugin = a;
        test.context = { bundle, neovim }: assert bundle.outPath == a.outPath; neovim;
      } ];
    }).context.outPath;
    expected = b.outPath;
  };
  testModuleDiscriminatorAsName = {
    expr = (checks [ { plugin = a; test._type = check; } ])._type.outPath;
    expected = a.outPath;
  };
  testEmptyChecks = {
    expr = builtins.attrNames (checks [ a ]);
    expected = [ ];
  };
  testNestedCollection = {
    expr = builtins.attrNames (checks [ {
      plugin = a;
      test.outer = check;
      dependPlugins = [ { plugin = b; test.inner = check; } ];
    } ]);
    expected = [ "inner" "outer" ];
  };
  testDisjointRepeatedTests = {
    expr = builtins.attrNames (checks [
      { plugin = a; test.first = check; }
      { plugin = a; test.second = check; }
    ]);
    expected = [ "first" "second" ];
  };
  testDuplicateSameFunction = invalid [
    { plugin = a; test.same = check; }
    { plugin = a; test.same = check; }
  ];
  testDuplicateDifferentFunctions = invalid [
    { plugin = a; test.same = check; }
    { plugin = a; test.same = _: b; }
  ];
  testDuplicateAcrossPackages = invalid [
    { plugin = a; test.same = check; }
    { plugin = b; test.same = check; }
  ];
  testDuplicateNested = invalid [
    { plugin = a; test.same = check; dependPlugins = [ { plugin = b; test.same = check; } ]; }
  ];
  testRejectNonFunction = invalid [ { plugin = a; test.bad = a; } ];
  testRejectNonSet = invalid [ { plugin = a; test = check; } ];
  testRejectEmptyName = invalid [ { plugin = a; test."" = check; } ];
  testRejectNonDerivation = {
    expr = (checks [ { plugin = a; test.bad = _: "not a check"; } ]).bad;
    expectedError.type = "ThrownError";
  };
  testRuntimeDoesNotRunChecks = {
    expr = (api.compile {
      plugins = [ { plugin = a; doc = "Only documentation"; test.broken = _: throw "not invoked"; } ];
    }).lua == (api.compile { plugins = [ a ]; }).lua;
    expected = true;
  };
  testShorthandDoesNotRepeatTests = {
    expr = builtins.attrNames (checks [
      { plugin = a; test.once = check; }
      { plugin = b; dependPlugins = [ a ]; }
    ]);
    expected = [ "once" ];
  };
  testFiniteCrossFileCycle = {
    expr = let
      groups = {
        first = { plugin = a; dependPlugins = [ groups.second.plugin ]; test.first = check; };
        second = { plugin = b; dependPlugins = [ groups.first.plugin ]; test.second = check; };
      };
      result = api.compile { plugins = builtins.attrValues groups; };
    in builtins.deepSeq result.lua {
      tests = builtins.attrNames result.graph.tests;
      cyclic = (builtins.head result.graph.units).cyclic;
    };
    expected = { tests = [ "first" "second" ]; cyclic = true; };
  };
  testRepeatedDocs = {
    expr = (api.compile { plugins = [
      { plugin = a; doc = "Same"; }
      { plugin = a; doc = "Same"; }
    ]; }).graph.nodes.${a.outPath}.settings.doc;
    expected = "Same";
  };
  testConflictingDocs = {
    expr = (api.compile { plugins = [
      { plugin = a; doc = "First"; }
      { plugin = a; doc = "Second"; }
    ]; }).lua;
    expectedError.type = "ThrownError";
  };
  testRejectNonStringDoc = {
    expr = (api.compile { plugins = [ { plugin = a; doc = 123; } ]; }).lua;
    expectedError.type = "ThrownError";
  };
  testRejectRootTestRegistry = {
    expr = (api.compile { plugins = [ a ]; test.bad = check; }).lua;
    expectedError.type = "ThrownError";
  };
  testCheckValuesRemainLazy = {
    expr = (checks [ { plugin = a; test = {
      selected = check;
      unselected = _: throw "not selected";
    }; } ]).selected.outPath;
    expected = a.outPath;
  };
  testDocsDoNotRunChecks = {
    expr = api.mkDocs {
      pkgs.writeText = _: text: text;
      configuration.plugins = [ {
        plugin = a;
        doc = "Inline prose";
        test.broken = _: throw "not invoked";
      } ];
    };
    expected = "# Configuration\n\n## a\n\nPackage: `${a.outPath}`\n\nDeclarations: `plugins[0]`\n\nInline prose\n";
  };
  testDuplicateNotHiddenByToolQuery = {
    expr = (api.resolve {
      plugins = [ { plugin = a; test.same = check; } { plugin = a; test.same = check; } ];
    }).extraPackages;
    expectedError.type = "ThrownError";
  };
}
