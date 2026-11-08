---
status: accepted
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/13"
---

# Propagate startup demand through prerequisite units

## Context and Problem Statement

Non-delayed targets must remain in `opt` and load during startup, including
declarations nested in dependencies. Omitted timing defaults to `false` after
merging repeated occurrences. Startup targets need their prerequisites even when
those prerequisites declare deferred loading, without inheriting or rewriting
any declaration's timing.

## Considered Options

- Seed startup demand from non-delayed nodes and propagate it through their SCC
  units' prerequisites, retaining all declared timing (existing implementation).

No competing policy or completed comparative experiment was recorded in the
acceptance review.

## Decision Outcome

Chosen option: "Propagate startup demand through prerequisite units", because a
startup target must have its prerequisites available while declared timing and
placement remain independent of the request that caused a load.

A resolved `lazy = false` (including the default) seeds demand for its SCC and
prerequisite closure. A dependency can be required at startup even if it declares
`lazy = true`. No flag is rewritten by demand propagation and every node remains
`opt`. Declarations with omitted timing seed startup demand themselves after the
existing default is applied. Merely belonging to a proposed package group does
not create another singleton startup declaration.

For example, if startup target A depends on B with `lazy = true`, load B before A
at startup and retain B's declared `lazy = true`. This is prerequisite demand,
not inherited timing. Trigger declarations do not implicitly enable deferral;
explicit `lazy = true` is still required. The complementary policy for deferred
targets without triggers is recorded in [ADR 0010](0010-triggerless-deferred-loading.md).

### Consequences

- Positive: Startup targets have their prerequisites without rewriting timing,
  inheriting a parent's flags or promoting packages to `start`.
- Negative: `lazy = true` does not promise that a dependency will remain unloaded
  until one of its own triggers fires. Consumers must distinguish declared timing
  from the demands made by other targets.

## Acceptance and Implementation Evidence

The project owner explicitly approved startup prerequisite demand, preservation
of declared timing, and the absence of implicit deferral from triggers in the
review recorded by the linked discussion. This acceptance is not inferred from
implementation or test results. The original prototype discussion remains in
[PR #1](https://github.com/ttak0422/divine/pull/1).

[lib/resolve.nix](../../lib/resolve.nix) computes startup demand, and the compiler
and runtime execute it. [tests/resolver.nix](../../tests/resolver.nix) covers
startup closure, cycles and opt placement. [tests/compiler.nix](../../tests/compiler.nix)
covers preserved deferred dependency timing, all five trigger categories without
implicit deferral, and omitted/default timing. Native opt-tree cases in
[tests/runtime-plan.lua](../../tests/runtime-plan.lua) cover prerequisite ordering
and loading an unrelated triggerless target only on a manual request.

Public names, repeated-definition conflict/merge policy, SCC extraction and
within-unit sequencing, package-group identity, and detailed trigger handoff are
separate decisions. This record does not accept those proposals or change the
before/load/after and `after/plugin` boundaries in [design.md](../design.md).
