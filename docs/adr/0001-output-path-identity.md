---
status: proposed
date: 2026-11-07
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Use output-path identity for finite back-references

## Context and Problem Statement

Roots and dependencies must accept the same recursively nested package shorthand
and detailed definitions. Cycles must form SCC load units, but the identity rule
and a finite way to express back-references remain open in
[the design requirements](../design.md). Directly cyclic Nix values are a separate
problem from a finite input describing a cyclic graph.

## Considered Options

- Package output-path identity, with package occurrences referring to detailed
  declarations elsewhere in the same finite input (current prototype).
- Explicit configuration IDs if multiple configurations of the same output are
  needed (alternative noted in [resolution.md](../resolution.md#identity-and-repeated-definitions),
  not implemented or rejected).

## Decision Outcome

Proposed option: "Package output-path identity", because it makes sharing and
finite back-references available without an additional reference field, as
recorded in [resolution.md](../resolution.md#input-and-finite-cycles).

Distinct output paths remain distinct even when display names match. Package
values and their build contexts are retained; string context is removed only
from identifiers used as keys. Shorthand contributes an occurrence without
assigning occurrence-level timing or configuration defaults. The resolver
applies the `lazy = false` default after merging repeated occurrences. Repeated settings are covered by
[ADR 0002](0002-repeated-definitions.md).

### Consequences

- Positive: A finite input can describe a cycle while preserving detailed
  definitions and recursive dependencies at every depth.
- Negative: The identity cannot distinguish multiple configurations of one
  output path. That use case needs further review, and directly cyclic Nix
  values remain outside this evaluator's finite input.

## Implementation and Open Questions

Implemented in [lib/resolve.nix](../../lib/resolve.nix), with finite-cycle,
self-dependency and distinct-output-path fixtures in
[tests/resolver.nix](../../tests/resolver.nix). Implementation is not acceptance.
An alternative identity/reference API and public names remain open.
