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
assert (builtins.head tree).definition.plugin == leaf;
assert !((builtins.head tree).definition ? lazy);
assert child.definition == dependency;
assert child.definition.lazy == false && root.definition.lazy == true;
assert (builtins.head child.dependencies).definition.plugin == leaf;
assert builtins.length root.dependencies == 2;
assert !(succeeds (api.inspectDefinitions false));
assert !(succeeds (api.inspectDefinitions [ { dependPlugins = [ ]; } ]));
assert
  !(succeeds (
    api.inspectDefinitions [
      {
        plugin = leaf;
        dependPlugins = false;
      }
    ]
  ));
assert
  !(succeeds (
    api.inspectDefinitions [
      {
        plugin = leaf;
        lazy = "unspecified";
      }
    ]
  ));
{
  passed = builtins.deepSeq tree (
    (import ./resolver.nix { inherit lib; }).passed && (import ./compiler.nix { inherit lib; }).passed
  );
  scope = "finite input inspection and SCC/dependency resolution; Lua plan compilation; runtime tested separately";
}
