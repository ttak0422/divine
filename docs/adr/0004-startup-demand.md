---
status: proposed
date: 2026-11-07
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Propagate startup demand through prerequisite units

## Context and Problem Statement

Explicitly non-delayed targets must remain in `opt` and load during startup,
including declarations nested in dependencies. Omitted timing defaults to `true`
after merging repeated occurrences.
The prototype needs to identify the prerequisite units for an explicit startup
demand without treating that demand as inherited timing declarations.

## Considered Options

- Seed startup demand from explicitly non-delayed nodes and propagate it through
  their SCC units' prerequisites, retaining all declared timing (prototype).

[resolution.md](../resolution.md#startup-demand-and-opt-placement) records this
review choice without a concrete alternative. No competing policy or completed
comparison is recorded here.

## Decision Outcome

Proposed option: "Propagate startup demand through prerequisite units", so the
output identifies the prerequisites of an explicit startup target while retaining
the original timing declarations. This describes the prototype's dependency-demand
rule; its adoption remains open for review.

An explicit `lazy = false` seeds demand for its SCC and prerequisite closure.
A dependency can be required at startup even if it declares `lazy = true`.
No flag is rewritten by demand propagation and every node remains `opt`. Nodes
whose timing defaults to `lazy = true` may also be required at startup.

### Consequences

- Positive: The graph identifies startup prerequisites without overriding timing
  defaults, inheriting a parent's flags or promoting packages to `start`.
- Negative: A declared deferred dependency can be demanded at startup by another
  node. Consumers must distinguish declared timing from demand; runtime scheduling
  and trigger handoff have provisional implementations that still need review.

## Implementation and Open Questions

Implemented as graph metadata in [lib/resolve.nix](../../lib/resolve.nix), with
startup-closure, cycle-startup, opt-placement and omitted-timing fixtures in
[tests/resolver.nix](../../tests/resolver.nix). Implementation is not acceptance.
The graph is connected to startup loading through the compiler and bundle in
[runtime.md](../runtime.md). Triggerless policy and detailed
runtime handoff remain open; the existing before/load/after
and `after/plugin` boundaries in [design.md](../design.md) are unchanged.
