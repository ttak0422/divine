# divine

Declare a Neovim configuration in Nix and load plugins with a small Lua runtime.

## Build a configuration

`lib.mkBundle` builds a directory containing `init.lua`, the runtime and plugins
in `pack/divine/opt`. Plugins load at startup by default.

With `pkgs` and divine's `lib` bound:

```nix
lib.mkBundle {
  inherit pkgs;
  configuration = {
    plugins = [
      {
        plugin = pkgs.vimPlugins.telescope-nvim;
        dependPlugins = [
          pkgs.vimPlugins.plenary-nvim
        ];
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

Run Neovim with `nvim -u /path/to/bundle/init.lua`.

- Declare required plugin dependencies in `dependPlugins`; divine does not use
  nixpkgs plugin `dependencies` to populate the bundle or determine loading.
  Both `plugins` and recursive `dependPlugins` accept packages or detailed
  definitions.
- For deferred loading, set `lazy = true` and a trigger such as
  `onCommands = "Telescope"`. Triggers alone do not defer loading. Dependencies
  default to startup loading independently of their parent.
- Plugins remain in `opt`, including those loaded at startup. Native startup may
  source unguarded plugin scripts again after `packadd`; divine does not
  automatically source deferred `after/plugin` scripts.

See the [runtime guide](docs/runtime.md) for configuration fields,
trigger syntax and loading behavior. The API is evolving, and broad third-party
plugin compatibility has not been verified.

## Keep definitions together

Split plugin families into ordinary Nix files while keeping each plugin's Lua
configuration, `doc` string and a single `test` function or named `tests` functions together. Use package
references for cross-file dependency edges and include each full definition once.

```nix
{
  bundle = lib.mkBundle { inherit pkgs configuration; };
  documentation = lib.mkDocs { inherit pkgs configuration; };
  checks = lib.mkChecks { inherit pkgs configuration; };
}
```

Checks are Nix functions returning derivations, so they can use Python/pynvim,
RPC, fixtures and editor restarts without adding tools to the runtime bundle.
See the [definition guide](docs/definitions.md) and
[grouped example](examples/definitions/default.nix) for this provisional API.

## Development

```sh
nix develop
make test
nix flake check --print-build-logs
prek run --all-files
```

`make test` runs the Nix and Lua suites. `nix flake check` also runs bundle and
real-plugin integration checks; `--no-build` only evaluates check definitions.
`nix fmt` runs the formatting and lint checks.

See the [contribution guide](CONTRIBUTING.md) for contribution formats and the
[implementation guidelines](docs/contributing.md) for coding and test
conventions.
See [ADR 0006](docs/adr/0006-use-nix-unit.md) and
[ADR 0007](docs/adr/0007-use-mini-test.md) for the test-method decisions.

## Documentation

- [Design requirements](docs/design.md)
- [Inline definitions, documentation and checks](docs/definitions.md)
- [Dependency resolution](docs/resolution.md)
- [Nix type reference](docs/nix-types.md)
- [Architecture decisions](docs/adr/README.md)
- [Planned work](TODO.md)
