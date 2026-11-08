---
status: proposed
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Prepare SCC runtimes before phased configuration

## Context and Problem Statement

Every member of a cyclic load unit must be available before associated
configuration runs. The graph's stable member list is not a dependency order
inside a cycle. Startup and deferred targets must share the same loading flow
and remain in opt, without automatic after/plugin sourcing by default.

## Considered Options

- Prepare every runtime with `packadd!`, then run all pre-load callbacks, all
  ordinary loads and all post-load callbacks in deterministic member order.

This is the implemented proposal. No alternative or completed comparative
experiment is recorded as adopted or rejected.

## Decision Outcome

Proposed option: separate runtime preparation from the three configuration/load
phases. This makes peer modules visible even to a pre-load callback, without
pretending that all peer plugin scripts have already executed.

Load prerequisite units first. Keep successful units loaded and failed units
failed; do not automatically retry partial effects. Reentry is allowed only
once every member runtime is prepared. A per-member replacement load function
can replace ordinary packadd, but not the common preparation phase.

The separate [after-directory proposal](0008-opt-in-after-loading.md) inserts
explicit `loadAfter` work after all ordinary loads and before configuration,
using the same synchronous sequence at startup and during deferred loading.
Its generated runtime view hides only opted-in `after/plugin` from native scans;
other after directories retain their own native lookup semantics.

### Consequences

- Positive: Cyclic peers have available module paths before callbacks, and shared
  dependencies and repeated triggers do not repeat successful runtime loads.
- Negative: Within-unit callback order and failure recovery remain review choices.
  Prepared paths and partial effects survive a failure. Native startup can scan
  unguarded plugin scripts again after an early packadd; this proposal preserves
  that native behavior rather than suppressing global plugin loading.

## Implementation and Open Questions

Implemented in [lua/divine/init.lua](../../lua/divine/init.lua) and tested by
[tests/runtime-plan.lua](../../tests/runtime-plan.lua) and the generated bundle
fixtures. [Runtime details](../runtime.md) distinguish controller idempotence,
ordinary startup scanning and after/plugin. Passing tests do not accept the
proposal. Public names, event replay edge cases and arbitrary
plugin compatibility remain open.
