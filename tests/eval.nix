{
  lib ? import <nixpkgs/lib>,
}:
let
  api = import ../lib { inherit lib; };
  # Derivation-shaped fixtures; these tests do not realize packages.
  package = name: {
    type = "derivation";
    inherit name;
    outPath = "/nix/store/00000000000000000000000000000000-${name}";
  };
  leaf = package "leaf";
  dependency = {
    plugin = package "dependency";
    lazy = false;
    preConfig = "vim.g.example = true";
    config = "require('example').setup({})";
    dependPlugins = [ leaf ];
    extensionMetadata = {
      retained = true;
    };
  };
  tree = api.inspectDefinitions [
    leaf
    {
      plugin = package "root";
      lazy = true;
      dependPlugins = [
        leaf
        dependency
      ];
    }
  ];
  root = builtins.elemAt tree 1;
  child = builtins.elemAt root.dependencies 1;
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
in
{
  testPackageShorthand = {
    expr = (builtins.head tree).definition.plugin == leaf;
    expected = true;
  };
  testShorthandHasNoTimingDefault = {
    expr = !((builtins.head tree).definition ? lazy);
    expected = true;
  };
  testRecursiveDefinitionRetained = {
    expr = child.definition == dependency;
    expected = true;
  };
  testIndependentParentAndDependencyTiming = {
    expr = child.definition.lazy == false && root.definition.lazy == true;
    expected = true;
  };
  testNestedDependency = {
    expr = (builtins.head child.dependencies).definition.plugin == leaf;
    expected = true;
  };
  testAllDependenciesInspected = {
    expr = builtins.length root.dependencies == 2;
    expected = true;
  };
  testRejectNonListInput = {
    expr = builtins.deepSeq ((api.inspectDefinitions false)) true;
    expectedError.type = "ThrownError";
  };
  testRejectMissingPlugin = {
    expr = builtins.deepSeq ((api.inspectDefinitions [ { dependPlugins = [ ]; } ])) true;
    expectedError.type = "ThrownError";
  };
  testRejectNonListDependencies = {
    expr = builtins.deepSeq (
      (api.inspectDefinitions [
        {
          plugin = leaf;
          dependPlugins = false;
        }
      ])
    ) true;
    expectedError.type = "ThrownError";
  };
  testRejectInvalidTiming = {
    expr = builtins.deepSeq (
      (api.inspectDefinitions [
        {
          plugin = leaf;
          lazy = "unspecified";
        }
      ])
    ) true;
    expectedError.type = "ThrownError";
  };
}
