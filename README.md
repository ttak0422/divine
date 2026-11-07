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
configuration dependencies, without package-wrapper promotion to start.
This example demonstrates the interface; the automated suite uses synthetic
plugins rather than claiming telescope compatibility.

See [runtime.md](docs/runtime.md) for executable plan structure, trigger syntax,
SCC phases, failure states and native startup limitations. Ordinary packadd during
init can be followed by another native scan of unguarded plugin scripts. The
runtime does not automatically source deferred `after/plugin`.

## Development

```sh
nix develop
nix flake check --print-build-logs
prek run --all-files
```

`nix fmt` runs git-hooks.nix/prek with nixfmt, StyLua and Luacheck. Nix functions
use nixdoc comments. The locked tools target Apple Silicon macOS and aarch64/x86_64
Linux. `nix flake check --no-build --all-systems` evaluates all check definitions;
it does not execute runtime checks or prove builds on every system.

The existing Nix runner has a known limitation: plain `make test` without
`NIXPKGS_LIB` can print `<LAMBDA>` without executing Nix assertions. A test-method
comparison remains open; this implementation does not select a new framework or
include the separate unapproved runner patch. Use the full flake check above, or
explicitly provide the pinned library:

```sh
NIXPKGS_LIB="$(nix eval --impure --raw --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')/lib" make test
```

The explicit path applies the fixture function; assertion failures return nonzero.
`make test-lua` runs the isolated load primitive, opt/SCC runtime and native trigger
fixtures. The flake also builds a fixture bundle and starts Neovim through its
generated init, checking placement, startup, command/module handoff, after/plugin
phases and collected tools. There is no NixOS VM or snapshot framework dependency.

## Design and review

- [Design requirements](docs/design.md) are the behavior contract.
- [Dependency resolution](docs/resolution.md) explains finite graphs and SCCs.
- [Runtime prototype](docs/runtime.md) documents current behavior and limitations.
- [ADRs](docs/adr/README.md) retain proposed decisions separately from implementation.
- [TODO.md](TODO.md) tracks remaining review choices and missing coverage.

No design decision becomes accepted merely because a test or implementation exists.
Third-party plugin compatibility and a separate Neovim 0.12.4 run remain unverified.
