# Cartridges: configuration, documentation and checks

This guide describes the provisional definition, documentation and check APIs.
A cartridge is an ordinary Nix file returning related plugin definitions, not
a module registry or a new import mechanism. Public names remain under review.

## Compose cartridges with ordinary imports

A file can return named definitions for a family of plugins. For example,
[the Telescope cartridge](../examples/cartridges/telescope.nix) keeps its package,
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
    test = { pkgs }: pkgs.runCommand "telescope-package" { } ''
      test -d ${pkgs.vimPlugins.telescope-nvim}
      touch "$out"
    '';
  };
}
```

Cartridges contain reusable components, not the complete configuration. Compose
them in [`examples/example.nix`](../examples/example.nix), which owns common
startup settings and can also declare simple plugins directly:

```nix
{ pkgs }:
let
  telescope = import ./cartridges/telescope.nix { inherit pkgs; };
  project = import ./cartridges/project.nix { inherit pkgs telescope; };
in
{
  plugins = [
    {
      plugin = pkgs.vimPlugins.mini-pairs;
      config = # lua
        ''
          require("mini.pairs").setup({ mappings = { ["'"] = false } })
        '';
    }
  ] ++ builtins.concatLists (map builtins.attrValues [ telescope project ]);
  startupConfig = # lua
    ''
      vim.g.mapleader = " "
    '';
}
```

A cartridge is optional: package shorthand or a detailed plugin definition can
appear directly in this configuration. Here mini.pairs automatically closes
parentheses, while the inline setting disables apostrophe pairing. The exported
example's smoke test types both characters and checks these effects. The separate
[`examples/plugins.nix`](../examples/plugins.nix) illustrates detailed declarations
and deferred-loading policy; it is not the runnable example's configuration.

The public `packages.<system>.example` output calls `lib.mkBundle` on
`examples/example.nix`; both the inline checks and startup smoke test use that
exported bundle. Build it with `nix build .#example`, then run installed Neovim
with `nvim -u ./result/init.lua`.

To reuse the complete configuration:

```nix
configuration = import ./examples/example.nix { inherit pkgs; };
```

The [project cartridge](../examples/cartridges/project.nix) enables the optional
Telescope projects picker and declares `dependPlugins = [ telescope.telescope.plugin ];`.
This dependency belongs to this configuration, not to project.nvim universally.
It ensures Telescope is configured before the project cartridge loads its extension.
The full Telescope definition is registered once at the root; resolution uses
package output-path identity to combine the reference with its configuration.

The example pins the original
[ahmedkhalf/project.nvim](https://github.com/ahmedkhalf/project.nvim/tree/8c6bad7d22eef1b71144b401c9f74ed01526a4fb)
with `buildVimPlugin` and a fixed source hash. The locked Nixpkgs attribute
`pkgs.vimPlugins.project-nvim` currently points to a different fork with a different
Lua API. This example uses the linked original's `require("project_nvim").setup(...)`
and its [optional Telescope integration](https://github.com/ahmedkhalf/project.nvim/blob/8c6bad7d22eef1b71144b401c9f74ed01526a4fb/README.md#telescope-integration).
It disables LSP detection and automatic root changes: use `:ProjectRoot` to
record a project, then `:Telescope projects` to revisit it.

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

## Share configuration across ordered packages

A definition can use `packages` instead of `plugin` when one config needs several
packages loaded in order. For example:

```nix
{
  packages = [
    pkgs.vimPlugins.nvim-cmp
    pkgs.vimPlugins.cmp-buffer
  ];
  loadAfter = true;
  config = # lua
    ''
      require("cmp").setup({ sources = { { name = "buffer" } } })
    '';
}
```

This prepares both runtimes, loads their scripts in order, sources opted-in
after/plugin scripts, then runs shared config. Startup is the default. Add
`lazy = true` and a trigger for deliberate deferral. `packages` is nonempty and
contains derivations only; put nested definitions in `dependPlugins`. Repeated
package outputs retain their first position.

Each declaration owns independent hooks even when its packages overlap another
one. Physical loading is shared, so an earlier load is not repeated or reordered
by a later group. A custom `load` receives each not-yet-loaded package's opt name;
its first loader wins. Explicit conflicting `loadAfter` policies for a shared
output fail; true applies across all its configurations.

A shorthand dependency on one member does not select the shared config. Place
the full packages definition in `dependPlugins` when that config must run first.
Copying a definition into several locations creates several configuration
occurrences, not a reusable identity. Internal location-derived IDs are not a
stable public interface. Use `tests.<name>`, not `test`, because a group has no
unique package-derived test name. The existing global test-name uniqueness rule
still applies. See [ADR 0009](adr/0009-ordered-package-units.md) for review status.

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

Use `test = { pkgs, ... }: ...` for one check, or `tests.foo = ...` and
`tests.bar = ...` for several named checks. Each function returns a derivation,
not a Lua snippet. A definition cannot contain both `test` and `tests`, even
when `tests` is empty. You may also use `tests.<name>` for a single check when
you want a custom stable output name. Keep checks next to the definition they describe:

```nix
{
  plugin = packages.example;
  tests.package = { pkgs }: pkgs.runCommand "package-check" { } "touch $out";
  tests.runtime = { pkgs, neovim }: pkgs.runCommand "runtime-check" { } ''
    ${neovim}/bin/nvim --headless -c 'qa!'
    touch "$out"
  '';
}
```

For a single check, an imported group can use:

```nix
{
  skk = {
    plugin = packages.skk;
    doc = "The configured SKK input method.";
    test = { pkgs, neovim }:
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

For a concrete example, the Telescope cartridge's check starts two fresh Neovim
processes through pynvim and asserts that its picker function is available.
That is an RPC/startup smoke test, not a picker-interaction or persistence test.
The project cartridge's check records a temporary project using `:ProjectRoot`,
asserts it appears in history, opens the real projects picker, checks its result
and closes it. Both imported example checks are included in the flake checks,
with isolated HOME/XDG directories. This does not cover every picker action or
project-history persistence across restarts.

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
`mkChecks` returns a flat attribute set of derivations suitable for `nix flake
check`. Plural `tests` uses the declared attribute names. Singular `test` uses
`lib.getName definition.plugin`, which uses `pname` when available or removes
the version suffix from `name`. Nix local group binding names are not available. In the complete example the
actual check names are `project.nvim` and `telescope.nvim`.
Defining a check does not execute it;
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
`skk.tests.skk-input`). Every duplicate name errors, including a duplicate on the
same package or the same function value registered twice. Singleton names also
collide with named tests and with other singleton packages of the same name.
Use `tests.<explicit-name>` with unique names such as `skk-input` and
`skk-restart` to resolve collisions; use package references for shared edges.

Documentation and test functions are build-time metadata. They do not appear in
the generated Lua runtime plan. Python, pynvim and other check-only tools belong
in check derivations, not `configuration.extraPackages`, and do not become
runtime dependencies merely because a definition declares a test.
