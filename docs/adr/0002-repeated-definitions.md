---
status: proposed
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Combine repeated definitions with explicit conflicts

## Context and Problem Statement

A package can occur at multiple roots or dependency locations. The prototype
needs to account for those occurrences without silently dropping settings or
inventing Lua and trigger ordering. Remaining composition policies stay open in [the design requirements](../design.md).
[ADR 0011](0011-normalize-repeated-trigger-forms.md) separately accepts comparison
after equivalent trigger normalization, with other differences remaining errors.

## Considered Options

- Combine complementary fields, accept equal repeated values, reject conflicting
  values, and form unions of dependency edges and external packages (prototype).

[resolution.md](../resolution.md#singleton-identity-and-repeated-definitions) leaves other
merge and conflict policies open without specifying a competing policy. No
additional option or completed comparison is recorded here.

## Decision Outcome

Proposed option: "Combine complementary fields and reject conflicts", because it
makes shared declarations useful while keeping ambiguous settings explicit
errors, the reason recorded in [resolution.md](../resolution.md#singleton-identity-and-repeated-definitions).

The comparison refinement in [ADR 0011](0011-normalize-repeated-trigger-forms.md)
is accepted independently of this broader proposal. Equivalent trigger forms use
a canonical comparison view; other fields retain exact typed equality, including
matching Nix string build contexts.
Nested attribute values must be equal rather than recursively merged. Conflicts
report the field, package and both input locations; incomparable values are not
silently selected. Lua text, trigger lists and arbitrary settings are not
concatenated. Edges and tools are deduplicated by the
[accepted package output-path identity](0001-output-path-identity.md) and sorted by path.
All occurrence locations remain in `origins`.

### Consequences

- Positive: Complementary declarations can share one node, with provenance and
  explicit diagnostics instead of hidden precedence or discarded values.
- Negative: Different values for a repeated field, including trigger lists that
  differ after normalization or nested settings, fail rather than composing
  automatically. Users must provide an explicit composed value when needed.

## Implementation and Open Questions

Implemented in [lib/resolve.nix](../../lib/resolve.nix), with repeated-definition,
conflict, string-context and recursive-tool fixtures in
[tests/resolver.nix](../../tests/resolver.nix). Implementation is not acceptance.
Review complementary-field composition, edge/tool unions and retained provenance
before treating those parts of this proposal as a public contract. ADR 0001 does
not accept them; ADR 0011 accepts only the comparison refinement and continued
conflicts for other unequal specifications.
