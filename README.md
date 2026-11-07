# divine

Pure Nix declarations and a small Lua runtime for a Neovim configuration.
This draft now builds executable opt-only bundles. Public names and several
runtime policies remain provisional; it is not yet a stable plugin manager.

## Build a configuration

The provisional library accepts the same package or detailed definition at roots
and in recursive `dependPlugins`. Compilation requires explicit load timing until
omitted timing is decided. For example, with `pkgs` and the project's `lib` bound:

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
use nixdoc comments. The locked tools target Apple Silicon macOS and aarch64/x86_64
Linux. `nix flake check --no-build --all-systems` evaluates all check definitions;
it does not execute the nix-unit or runtime tests or prove builds on every system.

`make test-nix` runs the locked flake's named suite through nix-unit, then tests
the runner's success, mismatch and unexpected-error exit behavior. It replaces
the previous default path that printed `<LAMBDA>` without executing assertions.
The suite contains 10 input, 30 resolver and 14 compiler cases, plus a discovery
regression that checks every expected case name to prevent empty suites from
passing unnoticed. Evaluation failures use nix-unit's `expectedError` contract.

The existing nixpkgs lock pins nix-unit 2.35.1, built against Nix 2.35.3 evaluator
components. No additional flake input or host daemon change is needed. This is
not a claim of testing a Lix-linked nix-unit variant. See
[ADR 0006](docs/adr/0006-use-nix-unit.md) for the selected method and boundaries.

With nix-unit and Neovim on PATH, a direct library path avoids evaluating the
flake during local tests:

```sh
make test NIXPKGS_LIB=/path/to/pinned/nixpkgs/lib
```

`NIX_UNIT=/path/to/nix-unit` can select an explicit executable. CI uses the pinned
package and imports the pinned library directly with a private evaluation store,
so its sandbox does not fetch the flake or access the host daemon. Full
`nix flake check` executes this check, while `--no-build` does not.

`make test-lua` runs the isolated load primitive, opt/SCC runtime and native trigger
fixtures. The flake also builds a fixture bundle and starts Neovim through its
generated init, checking placement, startup, command/module handoff, after/plugin
phases and collected tools. A separate `nixpkgs-dependencies` check reproduces
implicit dependency promotion with real text-object plugins and verifies divine's
explicit-only graph, shared selected dependency and actual text-object operations.
There is no NixOS VM or snapshot framework dependency.

## Design and review

- [Design requirements](docs/design.md) are the behavior contract.
- [Dependency resolution](docs/resolution.md) explains finite graphs and SCCs.
- [Runtime prototype](docs/runtime.md) documents current behavior and limitations.
- [ADRs](docs/adr/README.md) retain proposed decisions separately from implementation.
- [TODO.md](TODO.md) tracks remaining review choices and missing coverage.

No design decision becomes accepted merely because a test or implementation exists.
Broader third-party compatibility and a separate Neovim 0.12.4 run remain unverified.
