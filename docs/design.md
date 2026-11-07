# Design requirements

## Core approach

- Declare and resolve configuration in pure Nix, then load it dynamically with a
  lightweight Lua runtime.
- Define the Neovim configuration in Nix, arrange the required files at build
  time, and use the lightweight runtime for dynamic loading.
- Managed plugins and their dependencies normally belong in `opt`, including
  startup-loaded targets. Users are responsible for `after/`-related loading.
- Use a common plugin definition for startup and deferred targets rather than
  separate input lists. Explicitly load non-delayed targets at startup while
  keeping them in `opt`; do not move them to `start`. The loading runtime must
  be available during `init`.
- Accept a package alone or the same detailed definition at both roots and
  dependencies, with recursively nested dependencies.
- Write plugin-specific configuration in Lua. Automatic conversion of Nix
  `settings` attributes into plugin `setup` arguments is not needed here.
- Distinguish common startup configuration from configuration run before and
  after loading a target. Attribute and function names, and the loader/wrapper
  implementation approach, remain undecided.

## Package dependency metadata

Plugin-loading dependencies come only from divine's explicit declarations.
Ignore plugin dependencies recorded in a package derivation, including nixpkgs
Vim plugins' `dependencies`, when constructing the load graph, opt tree and
runtime plan. A dependency required at runtime must be declared explicitly with
the same recursive definition format, even if nixpkgs already lists it.

Do not clear or override the original derivation's dependency attributes to
implement this rule. Preserve its output, build/check dependencies and other
package metadata. Explicit divine plugin dependencies and global or recursive
`extraPackages` continue to work. This rule concerns automatic plugin loading,
not pruning Nix's build or runtime closure.

## Resolution strategy

- Let users describe dependency graphs freely, including cycles.
- Extract strongly connected components (SCCs), using an algorithm such as Tarjan's.
- Treat each SCC as one load unit.
- Process dependencies between SCCs as a DAG.
- Within an SCC, prepare every plugin's runtime before running configuration
  associated with plugin loading.

## Interface design

Build with Nix, assuming inline LSP and Tree-sitter support.

### Required expressiveness

Use the same definition format for startup and deferred targets, without
separate input lists. At both roots and dependencies, accept a package alone or
the same detailed definition. **A package alone is shorthand, not a restriction
on dependencies.** A detailed definition can contain the target package, load
timing, Lua configuration before and after loading, dependencies, and further
recursive detailed definitions within those dependencies.

Write plugin-specific configuration as Lua text or Lua files. Automatic
generation of plugin-specific `setup` arguments from Nix attributes is not
required. Common startup Lua configuration is separate from configuration run
before and after loading a target.

Use inline Nix strings annotated with `# lua` for configuration in documentation
and examples, so the Lua content is visible in place. Users can still split their
configuration into external Lua files; this presentation preference does not
remove that support.

### Examples and provisional names

The following is an **illustrative provisional syntax example** illustrating the required
expressiveness. `plugins`, `plugin`, `dependPlugins`, `lazy`, `preConfig`, `config`,
`onCommands` and `extraPackages` are provisional names for reading this example,
not finalized API names.

The fixed requirements concern common definitions, recursive dependencies,
configuration timing, placement and loading behavior, rather than names. Final
attribute names, schema and implementation functions will be decided
separately.

```nix
{ pkgs, ... }:
{
  plugins = [
    # A package alone is valid at both roots and dependencies.
    pkgs.vimPlugins.vim-repeat

    {
      plugin = pkgs.vimPlugins.telescope-nvim;
      lazy = true;
      dependPlugins = [
        pkgs.vimPlugins.plenary-nvim
        # Dependencies accept the same detailed definitions and further nesting.
        {
          plugin = pkgs.vimPlugins.vim-startuptime;
          lazy = false; # Load this at startup while keeping it in opt.
          preConfig = # lua
            ''
              vim.g.startuptime_tries = 10
            '';
          config = # lua
            ''
              vim.keymap.set("n", "<leader>st", "<cmd>StartupTime<cr>")
            '';
          dependPlugins = [ pkgs.vimPlugins.vim-repeat ];
        }
      ];
      onCommands = [ "Telescope" ];
      extraPackages = [ pkgs.ripgrep pkgs.fd ];
      config = # lua
        ''
          require("telescope").setup({})
        '';
    }
  ];
}
```

This example mixes packages alone with detailed definitions at both roots and
dependencies. Detailed dependencies also contain before/after configuration and
nested dependencies. `Telescope → vim-startuptime → vim-repeat` illustrates the
recursive structure, not the plugins' actual required dependencies.

An explicitly non-delayed detailed definition is a startup target that remains
in `opt`, even when nested in dependencies. This does not specify automatic
inheritance of the parent's load timing. The `lazy` option defaults to `true`
for package shorthand and detailed definitions with omitted timing, at every
dependency depth. Apply the default after merging occurrences of the same
package, preserving explicit timing declarations. Missing triggers do not imply
startup loading.

The inline after-load configuration in the example calls the plugin's own
`require("telescope").setup({})` API.

The before-load example supplies `vim.g.startuptime_tries` before the plugin reads
it during loading. The after-load example calls the plugin's Lua configuration
API after loading it. Annotate inline Lua in Nix with `# lua`; when splitting it
into another file, keep it as Lua.

### Normalization, identity and cycles

On the Nix side, normalize package shorthand into a form shared with detailed
definitions, validate nested dependencies and construct a graph. Do not replace
this with a restriction that prevents detailed definitions inside dependencies.

For repeated occurrences of the same package, the identity criterion, settings
merge policy and handling of conflicting load timing or configuration remain
undecided. The example includes `vim-repeat` twice, but does not specify silent
merging or discarding of occurrences.

Treat each SCC, including cycles, as one load unit. Cycles in the dependency graph
are distinct from evaluation of directly cyclic Nix values. The input
representation of cycles and a finite normalization method remain undecided.

### Placement and configuration timing

Managed targets and their dependencies normally belong in `opt`.
**Non-delayed targets remain in `opt` and are explicitly loaded at startup.**
A non-delayed declaration does not mean switching placement to `start`.
The example's `lazy = false` is provisional syntax for this non-delayed behavior.
Deferred targets load on their specified triggers.

```text
Common startup configuration: run during init, whether or not it needs a target's plugin code
Loading a target: before-load configuration (if needed) → load (default: packadd) → after-load configuration
Non-delayed target (opt): explicitly load in this order at startup
Deferred target with triggers (opt): use the same order on the first trigger
```

| Configuration role | Example contents |
| --- | --- |
| Before loading | Global values read by the plugin during loading; preparation of required dependencies |
| After loading | Setup through the plugin's Lua API; key mappings using that API |
| Common startup Lua configuration | Key prefixes; key mappings that invoke commands which load the plugin |

For example, common startup Lua configuration can contain the following. This
does not settle the input attribute name or adopt a third plugin field.

```nix
# lua
''
  vim.g.mapleader = " "
  vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
''
```

The relationship between before-load configuration, loading and after-load
configuration is the same for startup and deferred loading. The loader/wrapper
implementation approach and use of external libraries remain undecided; this
example alone does not select either.

### Lazy-loading triggers

Retain the following five trigger categories as requirements. They describe
functionality; the attribute and function names representing triggers remain
undecided.

| Trigger | Expected behavior | Example condition |
| --- | --- | --- |
| Neovim event | Load the target when the specified event occurs | An event for entering Insert mode |
| Command invocation | Load the target and hand off to the invoked command | `:Telescope` |
| Buffer filetype | Load the target when the filetype condition matches | A `nix` or `lua` buffer |
| Key operation | Load the target and hand off to the original key operation | The `<leader>ff` operation |
| Lua module require | Load the required plugin before resolving the requested module | `require("telescope.builtin")` |

For every trigger, the target stays in `opt` and enters the common flow of any
required before-load configuration, loading and after-load configuration.
Treat module names separately from plugin names. Loading on the key operation
itself is distinct from merely defining a key mapping in `init` that invokes a
command.

Retain the ability to express a single condition, multiple conditions or no
condition. Define condition syntax, module-name matching scope and the handoff
of the first operation or event during implementation; do not claim these are
already behaviorally verified.

Do not infer additional fixed requirements from features of individual APIs
that appear only in reference material, such as more specific event conditions
or loading triggered by another load.

### Loading behavior for after/

Use ordinary `packadd` as the default load operation. **Lazy-loading an `opt`
plugin after startup does not automatically source `after/plugin`.** For targets
that need `after/plugin`, users can supply explicit configuration, source it
manually or replace the load operation. No default dependency on, or automatic
introduction of, a helper library is selected.

For targets loaded with `packadd` during `init`, the `after/` directory is added
to the end of `runtimepath`. If normal plugin loading is enabled, Neovim's later
standard `after/plugin` loading phase handles it. A custom operation that also
sources it during `init` could execute it twice and is therefore not the default.
After-load configuration runs when the load operation returns; it does not
guarantee that all standard `after/plugin` loading has completed.

`after/ftplugin` follows a separate path: runtime lookup of `ftplugin` files for
`FileType`. Neither `packadd` nor after-load configuration is specified to execute
everything in the `after/` directory as one batch. This section defines loading
requirements; it does not claim that a custom load operation has been implemented
or tested in execution.

## Implementation status

This document describes required behavior. Input-definition inspection, a
dependency-resolution prototype and a small before/load/after primitive are
available. The prototype converts finite inputs into a graph, groups SCCs and
extracts dependency-first order and external packages. Provisional implementation
choices are recorded separately in [resolution.md](resolution.md); they are not
adopted as requirements or a final API.

Opt bundle generation, explicit startup loading, five trigger prototypes and SCC
runtime preparation are now implemented, with limitations recorded in
[runtime.md](runtime.md). [TODO.md](../TODO.md) separates remaining coverage and
review questions. Public names and detailed handoff policies are still
provisional. The syntax example uses the `lazy = true` default for shorthand.

## Coding rules

Follow the rules provided by git-hooks.nix (prek).

### Nix

- Follow [nixdoc](https://github.com/nix-community/nixdoc), with explicit `# Type`
  signatures for implementation functions; see [the type reference](nix-types.md).

### Lua

- Use [LuaLS annotations](https://luals.github.io/wiki/annotations/)
  to describe implementation function contracts and shared data types.
- Favor concise, one-line-style expressions where the linter and formatter allow.

Tests do not require type comments in either language. See
[contributing.md](contributing.md#coding-and-validation) for annotation and
validation guidance.

## Supported scope

- Lazy loading on events, command invocation, filetypes, key operations and Lua
  module requires, with single, multiple or omitted conditions. Concrete syntax
  and implementation approaches remain undecided.
- Documentation output.
- Splitting configuration across files.
- Adding runtime dependencies such as external commands.
- Configuration in forms such as `after/ftdetect`.

## Out of scope

- Native denops support (due to Deno runtime EOL).
- General hot swap, unload or reload of entire plugins as a standard feature.
