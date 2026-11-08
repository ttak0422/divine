# Inline definitions across files

This guide describes the provisional definition, documentation and check APIs.
The grouping shown here is ordinary Nix composition, not a module registry or a
new import mechanism. Public names remain under review.

## Group related plugins with ordinary imports

A file can return named definitions for a family of plugins. For example,
[the Telescope group](../examples/definitions/telescope.nix) keeps its package,
Lua configuration, documentation and check in one place:

```nix
{ pkgs }:
{
  telescope = {
    plugin = pkgs.vimPlugins.telescope-nvim;
    dependPlugins = [ pkgs.vimPlugins.plenary-nvim ];
    config = # lua
      ''
        require("telescope").setup({})
      '';
    doc = "Use :Telescope find_files to find files.";
    test.telescope-package = { pkgs }: pkgs.runCommand "telescope-package" { } ''
      test -d ${pkgs.vimPlugins.telescope-nvim}
      touch "$out"
    '';
  };
}
```

Import groups in a normal `let`, pass the values needed by another group and
include their full definitions in `configuration.plugins`:

```nix
let
  telescope = import ./telescope.nix { inherit pkgs; };
  goda = import ./goda.nix { inherit packages telescope; };
in
{
  plugins = builtins.attrValues telescope ++ builtins.attrValues goda;
}
```

Here `packages.goda` is a real derivation supplied by the caller, not an assumed
Nixpkgs attribute. The [complete example](../examples/definitions/default.nix)
can be imported as follows, with `myGodaPackage` bound to that derivation:

```nix
configuration = import ./examples/definitions {
  inherit pkgs;
  packages.goda = myGodaPackage;
};
```

The [Goda group](../examples/definitions/goda.nix) declares its illustrative edge
using `dependPlugins = [ telescope.telescope.plugin ];`. This references the
package, while the full Telescope definition is registered once at the root.
Resolution uses package output-path identity to combine the reference with its
full definition, including its configuration. The Goda-to-Telescope edge is an
example of composition, not a claim about either plugin's actual requirements.

A package reference does **not** import the rest of its definition. If the full
Telescope definition is not included anywhere, its configuration, documentation
and tests are not included either. A full definition may instead be nested in
`dependPlugins`, with all the same fields as at the root. Register a definition
containing tests only once: repeated test names are errors even when the same
function was reused.

This separation also permits finite cross-file cycles: register both full
definitions once and use their packages for back-references. Avoid recursively
embedding full definitions in each other, which creates an infinite Nix value.
See [dependency resolution](resolution.md) for identity and SCC behavior.

## Inline documentation

`doc` is an optional string on each detailed plugin definition, including nested
dependencies. It describes the user's configuration rather than generating a
reference from option declarations. Markdown can be written directly in it.

```nix
documentation = lib.mkDocs { inherit pkgs configuration; };
```

`mkDocs` returns a separate Markdown derivation. It does not change Neovim's
startup plan. For repeated occurrences of one package, identical `doc` values
merge under the existing settings-equality rule; different values conflict.
Documentation is not silently concatenated. See [resolution.md](resolution.md)
for the equality rule, including Nix string context.

## Inline checks are Nix functions

`test` is an attribute set of named Nix functions, not Lua snippets and not a
single implicit test. Each function returns a derivation. Keep tests next to the
definition they describe; an imported group can naturally use this shape:

```nix
{
  skk = {
    plugin = packages.skk;
    doc = "The configured SKK input method.";
    test.skk-input = { pkgs, neovim }:
      let
        python = pkgs.python3.withPackages (ps: [ ps.pynvim ]);
      in
      pkgs.runCommand "skk-input" { nativeBuildInputs = [ python ]; } ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_DATA_HOME="$HOME/data"
        export XDG_STATE_HOME="$HOME/state"
        export XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$HOME"
        python ${./tests/skk-input.py} ${neovim}/bin/nvim
        touch "$out"
      '';
  };
}
```

This SKK fragment is a **template**: provide `packages.skk`, its real
configuration/dependencies and your own `./tests/skk-input.py`. No SKK test suite
has been ported by this example. The script can use pynvim RPC to feed input,
assert buffer contents, inspect saved state, close the editor and start another
process using the same temporary state directories to test persistence. Keep
assertions and failure exit codes in the script; successful startup alone does
not establish input-method correctness. This retains ordinary Nix control over
tools, fixtures, build phases and multiple processes, rather than restricting
tests to a fixed Lua runner.

For a concrete example, the Telescope group's check starts two fresh Neovim
processes through pynvim and asserts that its picker function is available.
That is an RPC/startup smoke test, not a picker-interaction or persistence test.
The Goda check only verifies that the supplied package directory exists; it
makes no claim about Goda behavior.

## Export checks separately from the bundle

With divine's `lib`, `pkgs` and `configuration` bound:

```nix
let
  bundle = lib.mkBundle { inherit pkgs configuration; };
in
{
  packages.default = bundle;
  packages.documentation = lib.mkDocs { inherit pkgs configuration; };
  checks = lib.mkChecks { inherit pkgs configuration bundle; };
}
```

In a flake, put these package and check attributes beneath the relevant system,
for example `checks.${system} = lib.mkChecks { inherit pkgs configuration; };`.
`mkChecks` returns a flat attribute set of derivations keyed by the declared test
names, suitable for `nix flake check`. Defining a check does not execute it;
building the check derivation runs it.

The provisional call is:

```nix
lib.mkChecks {
  inherit pkgs configuration;
  # Optional: reuse a bundle or supply your own configured Neovim package.
  # bundle = lib.mkBundle { inherit pkgs configuration; };
  # neovim = myConfiguredNeovim;
}
```

Check functions receive only requested named arguments from:

- `pkgs`: the caller's Nixpkgs package set.
- `bundle`: the supplied bundle, or one built from `configuration` by default.
- `neovim`: the supplied Neovim package, or a generated wrapper exposing
  `bin/nvim` that starts Neovim with the bundle's `init.lua`.

Use named argument patterns, such as `{ pkgs }:` or `{ pkgs, neovim }:`.
The default bundle and wrapper are lazy: a package-only check does not build or
force them. Request `bundle` when a check wants to invoke its own Neovim with
`-u ${bundle}/init.lua`. A custom `neovim` must expose `bin/nvim` and apply the
intended configuration itself.

Test names must be globally unique across **all included definitions**, at roots
and dependency depths. They are not prefixed by the local Nix binding (`skk` in
`skk.test.skk-input`). Every duplicate name errors, including a duplicate on the
same package or the same function value registered twice. Use descriptive names
such as `skk-input` and `skk-restart`; use package references for shared edges.

Documentation and test functions are build-time metadata. They do not appear in
the generated Lua runtime plan. Python, pynvim and other check-only tools belong
in check derivations, not `configuration.extraPackages`, and do not become
runtime dependencies merely because a definition declares a test.
