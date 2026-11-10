# divine

## Development

```sh
nix develop
make test
nix flake check --print-build-logs
prek run --all-files
```

`make test` runs the Nix, Lua and graph-viewer suites. `nix flake check` also
runs generated-HTML, bundle and real-plugin integration checks; `--no-build` only evaluates check definitions.
`nix fmt` runs the formatting and lint checks.

See the [contribution guide](CONTRIBUTING.md) for contribution formats and the
[implementation guidelines](docs/contributing.md) for coding and test
conventions.
See [ADR 0006](docs/adr/0006-use-nix-unit.md) and
[ADR 0007](docs/adr/0007-use-mini-test.md) for the test-method decisions.

## Documentation

- [Design requirements](docs/design.md)
- [Cartridges, documentation and checks](docs/cartridges.md)
- [Offline dependency graph](docs/graph.md)
- [Dependency resolution](docs/resolution.md)
- [Nix type reference](docs/nix-types.md)
- [Architecture decisions](docs/adr/README.md)
- [Planned work](TODO.md)
- [Remaining policy reviews](docs/proposals/README.md)
