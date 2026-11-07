# Nix implementation types

The `# Type` sections in the Nix source files are nixdoc documentation, not
static Nix annotations or a new validation layer. They describe successful inputs and
results of the current prototype. Invalid inputs can throw, and Nix evaluates
values lazily: in particular, forcing a compiled `plan` or `lua` runs compiler
validation. These types do not settle the provisional public API or defaults.

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
  lazy? :: Bool,
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
package, dependency-list structure and optional boolean `lazy`; other fields
remain unconstrained at that stage. For resolution, every definition's optional
`extraPackages` must also be a package list. Missing `dependPlugins` and
`extraPackages` act as empty lists. Other definition fields become node `settings`,
and other root fields become graph `metadata`.

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
  unresolvedTiming :: [String],
  extraPackages :: [Package],
  metadata :: AttrSet
}
```

`units` are ordered prerequisite-first. `startupUnits` contains unit IDs;
`unresolvedTiming` contains node IDs. `Graph.extraPackages` includes global and
recursive tools, deduplicated by output path. `mergeSettings` returns a `values`
attribute set plus an `origins` map from each setting name to its first input
location; this map differs from each resolved node's list of occurrence origins.

## Compiler inputs and results

`CompilationConfiguration` is a `Configuration` restricted to the following root
and definition fields. Package shorthand and recursive detailed definitions still
work, but every resolved node must obtain explicit `lazy` timing from at least
one occurrence. Thus `lazy` may be absent on an individual declaration, but not
from a merged node. The resolver's conflict and finite-input rules still apply.

```text
LuaSource = String | Path
Conditions = String | [String]
KeyMode = "n" | "i" | "x" | "s" | "o" | "t"
KeyInput = String | { lhs :: String, mode? :: KeyMode }
Key = { lhs :: String, mode :: KeyMode }
CompilationDefinition = {
  plugin :: Package,
  dependPlugins? :: [Package | CompilationDefinition],
  extraPackages? :: [Package],
  lazy? :: Bool,
  preConfig? :: LuaSource,
  config? :: LuaSource,
  load? :: LuaSource,
  onEvents? :: Conditions,
  onCommands? :: Conditions,
  onFiletypes? :: Conditions,
  onKeys? :: KeyInput | [KeyInput],
  onModules? :: Conditions
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
