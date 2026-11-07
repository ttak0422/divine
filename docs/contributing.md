# Implementation guidelines

Follow the shared [contribution guide](../CONTRIBUTING.md) for project language,
issue and commit formats, and pull requests. This document covers implementation,
design review, examples and validation.

## Design and review

Follow the requirements in [design.md](design.md) and the review process in
[adr/README.md](adr/README.md). Do not resolve open design questions merely to
make a check pass. Root and dependency definitions must retain the same
recursive expressiveness. Do not introduce an external loader or automatically
source `after/plugin`.

## Configuration examples

Write configuration examples as inline Nix strings annotated with `# lua`, rather
than `builtins.readFile`. This is a documentation convention; users may still
split their configuration into external Lua files.

## Coding and validation

Run `make test` for changes to input inspection or runtime sequencing. Use the
git-hooks.nix/prek checks for Nix/Lua style. Nix functions use nixdoc comments.
Keep first-trigger and real-plugin tests distinct from isolated fixture checks.
See the [development instructions](../README.md#development) for commands and
[TODO.md](../TODO.md) for remaining test coverage.
