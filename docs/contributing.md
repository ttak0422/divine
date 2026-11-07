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
git-hooks.nix/prek checks for Nix/Lua style. Keep first-trigger and real-plugin
tests distinct from isolated fixture checks.
See the [development instructions](../README.md#development) for commands and
[TODO.md](../TODO.md) for remaining test coverage.

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
