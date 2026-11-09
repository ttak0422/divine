# Dependency resolution prototype — decisions for review

This implements finite dependency graphs, SCC load units, dependency-first DAG
ordering, and external-package extraction. The compiler now turns a graph with startup loading by default into an executable Lua load plan; see [runtime.md](runtime.md).
Package-node identity and finite package references are accepted in ADR 0001.
Public names, configuration-unit identity and the other policies described below
remain provisional. Runtime sequencing and trigger handoff have their own proposed
implementation boundaries.

Review status and reasoning are also indexed in the [ADRs](adr/README.md):
[identity and finite references](adr/0001-output-path-identity.md),
[repeated definitions](adr/0002-repeated-definitions.md),
[SCC extraction](adr/0003-prototype-scc-extraction.md), and
[startup demand](adr/0004-startup-demand.md). ADRs 0001 and 0004 are `accepted`; ADRs 0002
and 0003 remain `proposed`. [Triggerless deferred loading](adr/0010-triggerless-deferred-loading.md)
is accepted separately in ADR 0010. Existing implementations and passing tests do not
by themselves establish design acceptance.

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
remain valid. Directly cyclic Nix values are outside the finite-input contract.
This package-level identity/reference rule does not select the identity, grouping
or schema of reusable configuration units. The separate multi-package proposal
below does not amend ADR 0001.

## Explicit versus package dependencies

Only `dependPlugins` in divine definitions contributes plugin edges. A package's
own `dependencies` field is neither traversed nor evaluated for loading, including
when the package is shorthand or an explicitly declared dependency. Original
package values and their Nix dependency context are retained unchanged. The
resolver does not remove build inputs, propagated inputs or package metadata.
This loading boundary is a requirement in [design.md](design.md#package-dependency-metadata),
not an acceptance of the provisional repeated-definition or timing policies below.

## Singleton identity and repeated definitions

- **Identity (accepted):** the package's output path, not its display name, within
  one resolved graph. Distinct outputs remain distinct even if their names match.
  Configuration-unit identity, including any explicit ID for grouping or configuring
  packages, remains a separate API question.
- **Shorthand:** contributes a package occurrence without supplying any timing
  or configuration defaults. A detailed occurrence of that package can supply
  those fields elsewhere in the graph. After merging, omitted `lazy` defaults
  to `false`; explicit timing remains authoritative. Explicit `lazy = null` also
  means unspecified and is removed before comparing timing declarations. Null
  in other settings is not treated as omission.
- **Settings:** the current prototype combines fields supplied in separate
  occurrences. Repeated supplied fields compare canonical trigger views under
  [ADR 0011](adr/0011-normalize-repeated-trigger-forms.md), or exact typed values
  for other fields. Different values error with the package and both input
  locations. String equality includes Nix build context. Nested attribute values
  must be equal, not recursively merged. Functions or other values that cannot
  be compared are not silently chosen. The first supplied raw value is retained.
- **Trigger comparison:** singleton/list forms, existing event aliases/case and
  default key modes use the same form normalization as compilation. Equal string
  conditions deduplicate in first-occurrence order with context-sensitive
  equality; key duplicates remain significant. Distinct-element order is not
  sorted, and conditions from different declarations are not unioned. Omission
  does not insert an empty list. Malformed raw resolver metadata falls back to
  strict comparison; the compiler still rejects malformed supplied inputs.
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

Package identity and finite back-references are accepted independently of the
remaining policies in this section. ADR 0011 accepts comparison after equivalent
trigger normalization and conflicts for other unequal values. Complementary-field
composition, edge/tool unions and retained provenance remain the ADR 0002
proposal. Public names and any
configuration-unit or multi-package API also remain open; they are not accepted
as a side effect of the package-node decision.

## Ordered package configuration occurrences

The provisional `packages = [ a b ];` form is an alternative to `plugin = a;`,
not an additional field. It takes a nonempty derivation list, retaining the first
position of repeated output paths. Definitions inside the list are invalid; put
recursive definitions in `dependPlugins`, at roots or any dependency depth.

A packages declaration owns one shared `preConfig`, `config`, timing and trigger
set. Each occurrence is distinct even when another has the same package list or
identical settings. Unlike singleton declarations, those occurrences do not
merge settings by package identity. Internal IDs are derived from composed input
locations and may change when imports or list positions change; they are not
stable public references. See [ADR 0009](adr/0009-ordered-package-units.md), which
remains proposed independently of accepted physical output-path identity.

`dependPlugins` units load before the group. Every member runtime is prepared
before shared preConfig runs once. Each physical package not already loaded by
the controller then loads in declared order, followed by opted-in after/plugin
in that order and shared config once. Overlap does not rerun physical scripts,
but each configuration keeps its own hooks. A custom group `load` receives each
not-yet-loaded package's opt name; the first physical loader wins. An earlier
load can therefore override the later group's intended physical order or load
hook, without skipping its shared config. Native ordinary startup rescans are
not controlled by this deduplication.

A package shorthand dependency or manual controller `load(package_path)` selects
the singleton configuration, not the groups containing that package. Include a
full packages definition in `dependPlugins` when its shared config is required.
Copying it into another location creates another configuration occurrence; it
is not a finite group reference. Existing singleton finite cycles remain valid.

`loadAfter` is the exception to independent group settings: it controls physical
runtime isolation. Any explicit true applies to that output's loads through all
configurations. Omission is unspecified, while conflicting explicit true/false
values across singleton/group occurrences fail. Other shared settings do not
become settings on each member. Membership alone does not create an additional
singleton startup demand ahead of group preConfig.

Groups use explicit `tests.<name>` because `test` has no unique package name.
Test names remain globally unique, and group `doc` belongs to its occurrence.
Global and recursive external tools still form a deduplicated output-path union.

## SCCs and DAG order

Reachability uses Nix's cycle-safe `genericClosure`. Mutually reachable nodes
form SCCs, including singleton self-dependencies. SCCs are condensed into a DAG
and topologically ordered with prerequisites before their dependents.

The SCC graph contains singleton and group configuration vertices. Unit IDs use
the smallest configuration vertex ID; singleton-only graphs keep their existing
output-path IDs and ordering. Units retain configuration IDs separately from
flattened physical member IDs. Physical members follow first occurrence across
the configuration order, preserving each group's declared order where not
already encountered. The SCC configuration order is deterministic, not a
user-specified order inside a cycle: runtime integration must prepare every
member's runtime before the unit's related configuration. That integration is now implemented with proposed phased sequencing, documented in [runtime.md](runtime.md). The within-unit policy still needs review.

The simple reachability representation uses quadratic space in the worst case.
It favors inspectable code for initial graphs; measure before a large migration
and replace it with a more compact SCC algorithm if necessary.

## Startup demand and opt placement

Every physical node is marked `placement = "opt"`, including explicitly
non-delayed ones. A singleton declaration or group configuration with resolved
`lazy = false` (including the default) makes its SCC a startup demand; physical
membership alone does not create an extra singleton startup demand. That demand propagates
through the unit's prerequisites. A deferred dependency can therefore be required
at startup by a non-delayed parent, without changing its declared `lazy` value.
This dependency-demand rule is accepted in [ADR 0004](adr/0004-startup-demand.md);
it does not inherit or rewrite timing fields. Package-group identity and
occurrence semantics remain the separate ADR 0009 proposal.

Omitted timing defaults to `lazy = false` after repeated definitions are merged.
An explicit `lazy = true` node can still be pulled into a startup unit by
a prerequisite demand without changing its resolved timing. Triggers alone do
not imply deferred loading.
A triggerless deferred target loads only on prerequisite or manual demand, as
accepted in [ADR 0010](adr/0010-triggerless-deferred-loading.md). Public trigger
representations and detailed handoff remain open. Manual package-path loads
select singleton configuration, not containing groups; stable manual group
references are not established by this timing policy. The graph identifies
startup units; the compiler and bundle connect them to the runtime.

## External packages and validation

`extraPackages` contains the deduplicated union from the request and every
definition at every depth, including cyclic components. Original derivations
are retained. Extraction follows declared configuration dependencies, not an
inferred plugin API or a replacement for Nix's own build dependency closure.

Malformed input and conflicting metadata error before a caller can extract a
partial tool list and overlook an invalid graph. The output contains `nodes`,
`configurationNodes` for groups, ordered `units`, `roots`, `startupUnits`,
`extraPackages`, root `metadata` and collected `tests`; these names are internal prototype structure.

Pure evaluation tests cover shorthand, detailed/nested input, diamonds, sharing,
dependency-first order, cycles, self-dependencies, repeated and conflicting
settings, string contexts, startup demand, and global/recursive external tools.
These pure evaluation tests do not claim package builds or runtime behavior. Separate bundle and runtime fixtures cover those boundaries; see [runtime.md](runtime.md).
