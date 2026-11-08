# Nix implementation types

The `# Type` sections in the Nix source files are nixdoc documentation, not
static Nix annotations or a new validation layer. They describe successful inputs and
results of the current prototype. Invalid inputs can throw, and Nix evaluates
values lazily: in particular, forcing a compiled `plan` or `lua` runs compiler
validation. These types do not settle the provisional public API. The `lazy` default is `false`.

Notation follows the library's existing signatures: `::` describes a type,
`a -> b` is a function, `[a]` is a list, and `a | b` is a union. In the record
shapes below, `field? :: T` means an optional attribute, `...` permits additional
attributes, and `AttrsOf T` means an attribute set with values of type `T`.
`AttrSet` is an unrestricted attribute set. `a` and `b` are type variables;
`fail :: String -> a` never returns. `String`, `Path` and `Bool` are Nix values,
not their serialized Lua equivalents.

## Input and inspection

`Package` means a derivation recognized by `lib.isDerivation`, used as a plugin
or external tool. Resolution additionally uses its string-coercible output path
as identity. `Derivation` means a Nix derivation, such as the bundle or style-check
build result; `PackageSet` is the Nixpkgs package set supplied to a builder. `lib` in the implementation imports
is the Nixpkgs library attribute set, not divine's exported library.

```text
Definition = {
  plugin :: Package,
  dependPlugins? :: [Package | Definition],
  lazy? :: Bool | Null,
  ...
}
InspectedDefinition = {
  definition :: Definition,
  dependencies :: [InspectedDefinition]
}
Occurrence = {
  id :: String,
  origin :: String,
  definition :: Definition
}
Configuration = {
  plugins :: [Package | Definition],
  extraPackages? :: [Package],
  ...
}
```

Inspection preserves a detailed `definition` unchanged and converts a package
shorthand to `{ plugin = package; }`. Its `dependencies` are recursively inspected
children, not package values. Trees must be finite. Inspection checks only the
package, dependency-list structure and optional boolean-or-null `lazy`; other fields
remain unconstrained at that stage. For resolution, every definition's optional
`extraPackages` must also be a package list. Missing `dependPlugins` and
`extraPackages` act as empty lists. Named test functions are collected separately;
other definition fields become node `settings`, and other root fields become
graph `metadata`.

## Resolved graph

Node IDs are context-free output-path strings. Unit IDs are the smallest member
ID in each SCC. Keys of `nodes` are node IDs; dependency/member/root lists contain
IDs rather than nested nodes. Original packages retain their build context and
derivation metadata.

```text
ResolvedNode = {
  id :: String,
  package :: Package,
  placement = "opt",
  settings :: AttrSet,
  dependencies :: [String],
  extraPackages :: [Package],
  origins :: [String]
}
Unit = {
  id :: String,
  members :: [String],
  dependencies :: [String],
  cyclic :: Bool,
  startup :: Bool
}
Graph = {
  nodes :: AttrsOf ResolvedNode,
  units :: [Unit],
  roots :: [String],
  startupUnits :: [String],
  extraPackages :: [Package],
  metadata :: AttrSet,
  tests :: AttrsOf { run :: CheckFunction, origin :: String }
}
```

`units` are ordered prerequisite-first. `startupUnits` contains unit IDs;
`Graph.extraPackages` includes global and
recursive tools, deduplicated by output path. `mergeSettings` returns a `values`
attribute set plus an `origins` map from each setting name to its first input
location; this map differs from each resolved node's list of occurrence origins.

## Compiler inputs and results

`CompilationConfiguration` is a `Configuration` restricted to the following root
and definition fields. Package shorthand and recursive detailed definitions still
work. After merging occurrences, an omitted `lazy` defaults to `false`. Every
resolved node therefore has boolean `settings.lazy`, while individual declarations
may omit it or use `null` to leave timing unspecified. The resolver's conflict and finite-input rules still apply.

```text
LuaSource = String | Path
Conditions = String | [String]
KeyMode = "n" | "i" | "x" | "s" | "t"
KeyInput = String | { lhs :: String, mode? :: KeyMode }
Key = { lhs :: String, mode :: KeyMode }
CompilationDefinition = {
  plugin :: Package,
  dependPlugins? :: [Package | CompilationDefinition],
  extraPackages? :: [Package],
  lazy? :: Bool | Null,
  preConfig? :: LuaSource,
  config? :: LuaSource,
  load? :: LuaSource,
  onEvents? :: Conditions,
  onCommands? :: Conditions,
  onFiletypes? :: Conditions,
  onKeys? :: KeyInput | [KeyInput],
  onModules? :: Conditions,
  doc? :: String,
  test? :: CheckFunction
  tests? :: AttrsOf CheckFunction
}
CompilationConfiguration = {
  plugins :: [Package | CompilationDefinition],
  extraPackages? :: [Package],
  startupConfig? :: LuaSource,
  runtimePaths? :: [Path | Package]
}
```

Condition strings and key `lhs` strings must be nonempty. Condition/key lists
may be empty; omitted triggers become empty lists. A key's omitted `mode` becomes
`"n"`. Lua source strings may be empty; paths are read as files. Runtime paths
must be Nix paths or packages, not strings. No additional compiler root,
definition or key-record fields are accepted.

```text
LuaInline = { _type = "lua-inline", expr :: String }
Triggers = {
  events :: [String],
  commands :: [String],
  filetypes :: [String],
  keys :: [Key],
  modules :: [String]
}
PlanNode = {
  name :: String,
  triggers :: Triggers,
  before? :: LuaInline,
  after? :: LuaInline,
  load? :: LuaInline
}
PlanUnit = { id :: String, members :: [String], dependencies :: [String] }
Plan = {
  nodes :: AttrsOf PlanNode,
  units :: [PlanUnit],
  startup_units :: [String],
  startup? :: LuaInline
}
Compiled = {
  graph :: Graph,
  plan :: Plan,
  lua :: String,
  runtimePaths :: [Path | Package]
}
```

`LuaInline` is the locked Nixpkgs `lib.generators.mkLuaInline` record, not a Nix
function or a plain string. `callback` creates Lua function source inside that
record; `lib.generators.toLua` emits it as an unquoted expression in `Compiled.lua`.
Plan node keys remain graph node IDs, while each node's `name` is the hashed opt
directory name. Plan units omit the graph's `cyclic` and `startup` attributes.
Absent `runtimePaths` becomes an empty list; absent Lua source fields produce no
corresponding callback attribute. The bundle derivation exposes the original
resolved graph through `passthru.graph`.

## Module input adapter

The compiler validates its input with `lib.evalModules` and the `mkOption`
declarations in `lib/options.nix`. Root and definition options describe their
types and defaults. The adapter uses the same definition schema recursively at
all dependency depths and keeps package derivations opaque. Lua callbacks accept
strings or paths, triggers accept nonempty strings or lists, keys retain their
single-mode restriction, and runtime trees accept paths or packages.

`lazy` uses `types.nullOr types.bool` with `default = null`. The adapter
materializes this safe sentinel, but does not insert empty trigger lists into
individual occurrences. The resolver explicitly ignores null `lazy`
values, compares the remaining runtime/documentation fields, and applies `false` afterward.
Named tests are collected separately without comparing function values.
`nullOr` alone does not provide this merge policy. Explicit true/false conflicts
still fail in either order; null is not accepted as omission for other fields.

Package `_type` metadata is hidden only in a temporary validation view, so the
module evaluator cannot interpret it as an override. Returned package values
are the originals, including that metadata; it is never evaluated for loading.

Module evaluation validates each occurrence separately, rather than merging
repeated plugins as modules. This preserves exact typed equality (including
string context), whole-field conflicts, edge/tool unions and input locations.
The inspector and resolver still allow extension metadata; the compiler's
schema rejects unknown root, definition and key fields. The adapter is internal,
not a new public module API. Raw module properties such as `mkDefault` and
`mkMerge` are rejected before evaluation, rather than interpreted as input data; public names and existing proposed ADRs remain
provisional. Generated option documentation remains future work.

Event declarations accept native aliases and case variants. Compilation maps them
to unique Neovim 0.12.4 callback spellings; runtime plan event strings are canonical.
Unknown names fail during compilation, including for startup-loaded nodes.

## Inline documentation and checks

`CheckFunction` is a named-argument Nix function returning a derivation. Its
arguments are selected from `{ pkgs :: PackageSet, bundle :: Derivation,
neovim :: Derivation }`; unused arguments may be omitted, and other optional
arguments retain their defaults. The context values and individual check results
are lazy. A check requesting only `pkgs` does not evaluate or build the default
bundle or Neovim wrapper.

`doc` remains in the resolved node's settings but is omitted from the runtime
plan. Mutually exclusive `test` (one function) and `tests` (a named function map)
are collected separately into `Graph.tests`, with the function and
its declaration location. A singleton is named with `lib.getName definition.plugin`;
plural names are explicit attribute keys. Use `tests.<explicit-name>` for naming
collisions. Names are globally unique across the finite input
occurrences; repeated names fail even if their functions are the same value.
Tests never enter the general settings-equality comparison. These functions are
not invoked by resolution, compilation, bundle construction or documentation.

`mkChecks` returns a flat `AttrsOf Derivation`, suitable for flake checks, and
rejects a selected function that returns a non-derivation. Its optional `bundle`
and `neovim` arguments allow an existing runtime to be reused. The default
wrapper provides `bin/nvim` using `pkgs.neovim-unwrapped` and the bundle's
`init.lua`; an explicitly supplied wrapper owns its startup configuration.

`mkDocs` returns a Markdown derivation with package identities, declaration
locations and inline documentation. Locations identify entries in the composed
configuration, not original source-file line numbers. Both builders remain
separate from `mkBundle`; none of their outputs or test-only inputs are linked
into the runtime tree. See [the cartridge guide](cartridges.md).
