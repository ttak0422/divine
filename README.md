# divine

Pure Nix declarations and a small Lua runtime for a Neovim configuration.
This is an implementation starting point, not a usable plugin manager yet.

## Development

```sh
nix develop
make test
prek run --all-files
```

`nix fmt` runs the configured formatting/lint hooks. `nix flake check` also
evaluates the input fixtures and runs the isolated Lua tests.
The development shell uses git-hooks.nix with prek, nixfmt, StyLua and Luacheck.
Nix functions use nixdoc-compatible doc comments.
The locked development tooling targets Apple Silicon macOS and aarch64/x86_64 Linux.

The [design snapshot](docs/design.md) records the current behavior requirements.
[TODO.md](TODO.md) separates undecided behavior from missing implementation.
All names in `lib/`, `lua/` and `examples/` are provisional internal scaffolding.
There is no stable public API or Neovim package output.

## What works in this draft

- Inspect finite recursive inputs containing package shorthand and detailed
  definitions at either the root or a dependency.
- Preserve supplied metadata and repeated occurrences without choosing defaults,
  using the standalone input inspector.
- Resolve finite graphs into dependency-first SCC units, including cycles and
  self-dependencies, and extract global/recursive external package requirements.
- Diagnose conflicting settings while retaining omitted timing, provenance and
  opt placement. [Resolution choices](docs/resolution.md) are provisional and
  explicitly open for review.
- Run a Lua before action, an injected/default `packadd`, then an after action.
  No `after/plugin` sourcing is added.
- Evaluate small Nix fixtures and run Lua tests without loading real plugins.

Packaging into `opt`, startup orchestration, generated Lua, all five lazy
triggers, runtime preparation of SCCs and generated documentation remain TODOs.
Neither the input inspector nor the resolved graph is an executable Lua load
plan. Missing trigger registration deliberately reports an error.

## Local checks without a development shell

With Nix and Neovim already installed:

```sh
make test NIXPKGS_LIB=/path/to/nixpkgs/lib
```

The default is `import <nixpkgs/lib>`. These tests cover finite input inspection,
dependency resolution and the isolated load primitive; they do not test
packaging, lazy-trigger handoffs, real plugins, or Neovim 0.12.4 compatibility.
