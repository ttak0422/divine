# divine

Pure Nix declarations and a small Lua runtime for a Neovim configuration.
This draft now builds executable opt-only bundles. Public names and several
runtime policies remain provisional; it is not yet a stable plugin manager.

## Build a configuration

The provisional library accepts the same package or detailed definition at roots
and in recursive `dependPlugins`. The `lazy` option defaults to `true` for both
forms. Set `lazy = false` to request startup loading. For example, with `pkgs` and the project's `lib` bound:

```nix
lib.mkBundle {
  inherit pkgs;
  configuration = {
    plugins = [
      {
        plugin = pkgs.vimPlugins.telescope-nvim;
        lazy = true;
        dependPlugins = [
          { plugin = pkgs.vimPlugins.plenary-nvim; lazy = true; }
        ];
        onCommands = "Telescope";
        config = # lua
          ''
            require("telescope").setup({})
          '';
      }
    ];
    extraPackages = [ pkgs.ripgrep pkgs.fd ];
    startupConfig = # lua
      ''
        vim.g.mapleader = " "
        vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
      '';
  };
}
```

Run Neovim with `nvim -u /path/to/bundle/init.lua`. Explicit `lazy = false` entries
stay in opt and load during init. The bundle places only explicitly declared
configuration dependencies, ignoring nixpkgs plugin `dependencies` for loading
without rewriting the original derivations or promoting plugins to start.
Required runtime plugins must be declared explicitly, as above. The test suite
covers synthetic plugins and a real text-object dependency regression; it does
not yet claim telescope compatibility.

See [runtime.md](docs/runtime.md) for executable plan structure, trigger syntax,
SCC phases, failure states and native startup limitations. Ordinary packadd during
init can be followed by another native scan of unguarded plugin scripts. The
runtime does not automatically source deferred `after/plugin`.

## Development

```sh
nix develop
make test
nix flake check --print-build-logs
prek run --all-files
```

`nix fmt` runs git-hooks.nix/prek with nixfmt, StyLua and Luacheck. Nix functions
use nixdoc type comments; [the type reference](docs/nix-types.md) describes their
input and result shapes. Lua implementation uses LuaLS annotations, following
[the coding rules](docs/contributing.md#lua-types). Test functions do not need
type comments in either language. The locked tools target Apple Silicon macOS and aarch64/x86_64
Linux. `nix flake check --no-build --all-systems` evaluates all check definitions;
it does not execute the nix-unit or runtime tests or prove builds on every system.

`make test-nix` runs the locked flake's named suite through nix-unit, then tests
the runner's success, mismatch and unexpected-error exit behavior. It replaces
the previous default path that printed `<LAMBDA>` without executing assertions.
The suite contains 10 input, 30 resolver and 16 compiler cases, plus a discovery
regression that checks every expected case name to prevent empty suites from
passing unnoticed. Evaluation failures use nix-unit's `expectedError` contract.

The existing nixpkgs lock pins nix-unit 2.35.1, built against Nix 2.35.3 evaluator
components. No additional flake input or host daemon change is needed. This is
not a claim of testing a Lix-linked nix-unit variant. See
[ADR 0006](docs/adr/0006-use-nix-unit.md) for the selected method and boundaries.

With nix-unit and Neovim on PATH and `MINI_TEST` pointing to the pinned
mini.test package, a direct library path avoids evaluating the flake during local
tests:

```sh
make test NIXPKGS_LIB=/path/to/pinned/nixpkgs/lib MINI_TEST=/path/to/mini.test
```

`NIX_UNIT=/path/to/nix-unit` can select an explicit executable. CI uses the pinned
package and imports the pinned library directly with a private evaluation store,
so its sandbox does not fetch the flake or access the host daemon. Full
`nix flake check` executes this check, while `--no-build` does not.

`make test-lua` runs 53 named mini.test cases: 6 load-primitive, 19 runtime-plan
and 28 native-trigger cases. The development shell and `checks.<system>.runtime`
use `pkgs.vimPlugins.mini-test` (0.18.0) from the existing nixpkgs lock. It is a
test-only dependency, never part of generated divine bundles or user runtime
paths. No additional flake input or lock update is needed.

Each case starts a fresh headless Neovim process and temporary opt tree through
mini.test setup/cleanup hooks. The child does not load mini.test. Editor state,
module caches, command/trigger stubs, globals, buffers and package paths cannot
leak between cases. The explicit case-name inventory in `tests/cases.lua` catches
missing scenarios. Runner guards verify success, deliberate assertion failure,
empty-suite and collection-error exits, including cleanup after a failing case.
See [ADR 0007](docs/adr/0007-use-mini-test.md) for the chosen test method.

To run one suite in the development shell:

```sh
nvim --headless -u NONE --noplugin -n -i NONE -l tests/run.lua tests/triggers.lua
```

The flake's bundle and `nixpkgs-dependencies` checks remain plain headless Neovim
integration tests, without mini.test. The generated-init bundle checks placement,
startup, command/module handoff, after/plugin phases and collected tools. The
real text-object plugins check implicit dependency promotion, divine's
explicit-only graph, a shared selected dependency and actual text-object
operations. These startup/plugin phases must not be replaced by a test harness
that changes Neovim startup. There is no NixOS VM or snapshot framework dependency.

## Design and review

- [Design requirements](docs/design.md) are the behavior contract.
- [Dependency resolution](docs/resolution.md) explains finite graphs and SCCs.
- [Runtime prototype](docs/runtime.md) documents current behavior and limitations.
- [ADRs](docs/adr/README.md) retain proposed decisions separately from implementation.
- [TODO.md](TODO.md) tracks remaining review choices and missing coverage.

No design decision becomes accepted merely because a test or implementation exists.
Neovim support targets the default `pkgs.neovim` provided by the selected nixpkgs
revision. A separate run against Neovim 0.12.4 is not required. Broader third-party
plugin compatibility remains unverified.
