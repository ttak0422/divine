# Dependency resolution prototype — decisions for review

This implements finite dependency graphs, SCC load units, dependency-first DAG
ordering, and external-package extraction. The compiler now turns a graph with startup loading by default into an executable Lua load plan; see [runtime.md](runtime.md).
Names and the following choices are provisional review decisions, not final API
or design requirements. Runtime sequencing and trigger handoff have their own proposed implementation boundaries.

Review status and reasoning are also indexed in the [ADRs](adr/README.md):
[identity and finite references](adr/0001-output-path-identity.md),
[repeated definitions](adr/0002-repeated-definitions.md),
[SCC extraction](adr/0003-prototype-scc-extraction.md), and
[startup demand](adr/0004-startup-demand.md). All four remain `proposed`; the
implementation described below does not establish design acceptance.

## Input and finite cycles

`lib.resolve { plugins = [ ... ]; extraPackages = [ ... ]; }` accepts the same
package shorthand or detailed definition at roots and recursively in dependencies.
Global `extraPackages` and every definition's `extraPackages` are package lists.
Other root metadata is retained in `metadata`; other definition fields, including
Lua text and trigger declarations, are retained in each node's `settings`.

With `a` and `b` bound to package derivations, this is a finite input for a cycle:

```nix
{
  plugins = [
    { plugin = a; dependPlugins = [ b ]; }
    { plugin = b; lazy = true; dependPlugins = [ a ]; }
  ];
}
```

The package occurrences refer to nodes declared elsewhere in the same input.
This needs no additional reference field and does not construct an infinitely
recursive Nix value. Both detailed definitions and deeper nested dependencies
remain valid. Directly cyclic Nix values are still outside this evaluator's
finite input; an alternative reference/identity API remains open for review.

## Explicit versus package dependencies

Only `dependPlugins` in divine definitions contributes plugin edges. A package's
own `dependencies` field is neither traversed nor evaluated for loading, including
when the package is shorthand or an explicitly declared dependency. Original
package values and their Nix dependency context are retained unchanged. The
resolver does not remove build inputs, propagated inputs or package metadata.
This loading boundary is a requirement in [design.md](design.md#package-dependency-metadata),
not an acceptance of the provisional identity or timing policies below.

## Identity and repeated definitions

- **Identity:** the package's output path, not its display name. Distinct output
  paths remain distinct even if their names match. An explicit configuration ID
  is an alternative if multiple configurations of the same output are needed.
- **Shorthand:** contributes a package occurrence without supplying any timing
  or configuration defaults. A detailed occurrence of that package can supply
  those fields elsewhere in the graph. After merging, omitted `lazy` defaults
  to `false`; explicit timing remains authoritative. Explicit `lazy = null` also
  means unspecified and is removed before comparing timing declarations. Null
  in other settings is not treated as omission.
- **Settings:** combine fields supplied in separate occurrences. Repeating an
  identical typed value is accepted; different values for the same field error
  with the package and both input locations. String equality includes Nix build
  context. Nested attribute values must be equal, not recursively merged.
  Functions or other values that cannot be compared are not silently chosen.
- **Inline tests:** `test` is one check function, named with `lib.getName` of the
  plugin package; `tests` maps explicit names to functions. Reject both forms on
  one definition, including an empty `tests` map. Collect
  functions separately from settings, retaining their declaration locations.
  Names are globally unique; collisions require `tests.<explicit-name>` with unique
  names. Duplicates error across all occurrences, even for the same package or
  function. Function bodies are not evaluated during resolution. Use package
  references for shared edges so a full definition owns its tests once.
- **Inline docs:** `doc` follows the existing settings-equality rule. Equal
  strings merge; conflicting strings error. It is omitted from the Lua plan.
- **Edges and tools:** dependency edges and external packages form unions,
  deduplicated by output path and sorted by path. Lua text, trigger lists, and
  arbitrary settings are never concatenated as a guessed merge policy.
- **Provenance:** all occurrence locations remain in `origins`. The first
  package value represents an identity; its Nix build context is retained.
  Only identifiers discard string context so they can be used safely as keys.

This makes sharing and finite back-references useful immediately, while keeping
ambiguous settings explicit errors. Alternative identity, merge and conflict
policies need review; this prototype must not become the final policy by accident.

## SCCs and DAG order

Reachability uses Nix's cycle-safe `genericClosure`. Mutually reachable nodes
form SCCs, including singleton self-dependencies. SCCs are condensed into a DAG
and topologically ordered with prerequisites before their dependents.

Unit IDs use their smallest member output path. Independent units and member
lists are deterministic by path. A member list is not an executable order of
configuration callbacks within a cycle: runtime integration must prepare every
member's runtime before the unit's related configuration. That integration is now implemented with proposed phased sequencing, documented in [runtime.md](runtime.md). The within-unit policy still needs review.

The simple reachability representation uses quadratic space in the worst case.
It favors inspectable code for initial graphs; measure before a large migration
and replace it with a more compact SCC algorithm if necessary.

## Startup demand and opt placement

Every node is marked `placement = "opt"`, including explicitly non-delayed ones.
A resolved `lazy = false` (including the default) makes its SCC a startup demand. That demand propagates
through the unit's prerequisites. A deferred dependency can therefore be required
at startup by a non-delayed parent, without changing its declared `lazy` value.
This dependency-demand rule is a review choice, not timing-field inheritance.

Omitted timing defaults to `lazy = false` after repeated definitions are merged.
An explicit `lazy = true` node can still be pulled into a startup unit by
a prerequisite demand without changing its resolved timing. Triggers alone do
not imply deferred loading.
Triggerless deferred inputs and runtime trigger handoff are not decided here.
The graph identifies startup units; the separate compiler and bundle connect them to the runtime.

## External packages and validation

`extraPackages` contains the deduplicated union from the request and every
definition at every depth, including cyclic components. Original derivations
are retained. Extraction follows declared configuration dependencies, not an
inferred plugin API or a replacement for Nix's own build dependency closure.

Malformed input and conflicting metadata error before a caller can extract a
partial tool list and overlook an invalid graph. The output contains `nodes`,
ordered `units`, `roots`, `startupUnits`, `extraPackages` and
root `metadata` and collected `tests`; these names are internal prototype structure.

Pure evaluation tests cover shorthand, detailed/nested input, diamonds, sharing,
dependency-first order, cycles, self-dependencies, repeated and conflicting
settings, string contexts, startup demand, and global/recursive external tools.
These pure evaluation tests do not claim package builds or runtime behavior. Separate bundle and runtime fixtures cover those boundaries; see [runtime.md](runtime.md).
