# Implementation guidelines

Follow the shared [contribution guide](../CONTRIBUTING.md) for project language,
issue and commit formats, and pull requests. This document covers implementation,
design review, examples and validation.

## Design and review

Follow the requirements in [design.md](design.md) and the review process in
[adr/README.md](adr/README.md). Do not resolve open design questions merely to
make a check pass. Root and dependency definitions must retain the same
recursive expressiveness. Do not introduce an external loader or source `after/plugin` by default.
Explicit `loadAfter` handling is separate from the `config` callback.

## Configuration examples

Write configuration examples as inline Nix strings annotated with `# lua`, rather
than `builtins.readFile`. This is a documentation convention; users may still
split their configuration into external Lua files.

Omit `lazy = false` in ordinary configuration examples: startup loading is the
default. Use `lazy = true` for intentional deferral. Keep explicit `false` where
it explains the API contract or matters to a repeated-definition or conflict
test; omission is unspecified until declarations are merged.

## Coding and validation

Run `make test` for changes to input inspection or runtime sequencing. Use the
git-hooks.nix/prek checks for Nix/Lua style. Keep first-trigger and real-plugin
tests distinct from isolated fixture checks.
See the [development instructions](../README.md#development) for commands and
[TODO.md](../TODO.md) for remaining test coverage.

### Lua tests

Use mini.test named cases for the Lua suites, run with `make test-lua` in
`nix develop`. Add each scenario to the explicit inventory in `tests/cases.lua`;
an empty suite or a missing expected case must fail. `tests/helpers.lua` starts a
fresh Neovim child and temporary fixture tree per case and cleans both up after
failures. Child callbacks use their fixture argument, rather than captured Lua
upvalues, because they execute in another process.

Keep mini.test test-only, pinned through the existing nixpkgs lock. Do not load
it into the child editor or the generated runtime bundle. Preserve the separate
plain headless bundle/startup and real-plugin checks. The mini.test runner guard
must keep verifying nonzero assertion, empty-suite and collection-error results,
not merely successful test execution.

### Nix types

Document Nix implementation functions with nixdoc comments and explicit `# Type`
signatures. Describe actual input and result shapes, including optional fields
and higher-order functions; use [nix-types.md](nix-types.md) for shared names.
These comments document contracts, not static Nix type checking.

### Lua types

Use [LuaLS annotations](https://luals.github.io/wiki/annotations/) for Lua
implementation types. The [original wiki reference](https://github.com/LuaLS/lua-language-server/wiki/Annotations)
now points to this maintained documentation. Document function parameters and returns with
`---@param` and `---@return`, and describe shared records and variants with
`---@class`, `---@field` and `---@alias` where useful. Use `---@type` for values
whose intended type is not clear from inference. Keep optional values, callback
arguments and runtime states faithful to the implementation. Do not add blanket
casts or diagnostic suppression merely to make annotations appear valid.

Type comments are not required in tests, for either Nix or Lua. Annotations do
not replace runtime validation or execution tests. StyLua and Luacheck check
formatting and lint, not LuaLS types; report a LuaLS diagnostic run separately
when one is performed.
