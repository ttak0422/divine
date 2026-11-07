---
status: proposed
date: 2026-11-07
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Use mutual reachability for prototype SCC extraction

## Context and Problem Statement

[The design requirements](../design.md) already require SCC load units, a DAG
between units, and preparation of every member's runtime before related
configuration. This record concerns the prototype's extraction algorithm, not
whether cycles are supported or how callbacks execute within a unit.

## Considered Options

- Compute cycle-safe reachability with Nix `genericClosure`, then group mutually
  reachable nodes (current prototype).
- A more compact SCC algorithm, such as Tarjan's algorithm (mentioned in the
  design requirements; not implemented or benchmarked here).

## Decision Outcome

Proposed option: "Mutual reachability", because the simple representation favors
inspectable code for initial graphs, as recorded in
[resolution.md](../resolution.md#sccs-and-dag-order).

The prototype includes singleton self-dependencies, condenses components into a
DAG and orders prerequisites before dependents. Unit IDs use the smallest member
output path. Deterministic member lists are not a callback execution order.

### Consequences

- Positive: The initial resolver has an inspectable way to handle finite cycles
  and self-dependencies while producing dependency-first units.
- Negative: Reachability storage uses quadratic space in the worst case. Measure
  before a large migration and consider a more compact algorithm if needed.

## Implementation and Open Questions

Implemented in [lib/resolve.nix](../../lib/resolve.nix), with ordering, cycle and
self-dependency fixtures in [tests/resolver.nix](../../tests/resolver.nix).
Implementation is not acceptance, and no scalability benchmark is claimed.
SCC runtime preparation is now implemented separately, using the proposed phases
in [ADR 0005](0005-scc-runtime-phases.md). The graph is compiled into a Lua plan;
within-unit sequencing remains a review decision.
