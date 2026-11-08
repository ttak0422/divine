---
status: accepted
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/13"
---

# Allow deferred targets without triggers

## Context and Problem Statement

A deferred target may be needed only as a prerequisite or through an explicit
manual request. Requiring it to declare its own trigger would add an unrelated
loading condition. The design requires omitted, single and multiple conditions,
but concrete public representations remain a separate API decision.

## Considered Options

- Allow `lazy = true` without triggers, loading only when a prerequisite or manual
  request demands the target (existing implementation).

No competing policy or completed comparative experiment was recorded in the
acceptance review.

## Decision Outcome

Chosen option: "Allow deferred targets without triggers", because prerequisite
and manual requests provide valid loading paths without an independent trigger.

A target with `lazy = true` and no triggers does not request startup loading by
itself. It loads when another requested target needs it as a prerequisite, or
when explicitly requested manually. Prerequisite demand applies to startup,
triggered and manual loads. [ADR 0004](0004-startup-demand.md) specifies startup
demand without rewriting declared timing. Trigger declarations do not implicitly
set `lazy = true`; omission still follows the existing startup default.

This accepts the behavior, not a stable manual-call or group-reference API. The
current internal controller's `load(package_path)` selects the singleton
configuration, not every group containing that package. Package groups have no
stable public manual reference; including a full group definition as a dependency
uses the still-proposed occurrence semantics in [ADR 0009](0009-ordered-package-units.md).

### Consequences

- Positive: Dependencies and manually requested targets need no artificial event,
  command, key, filetype or module trigger.
- Negative: A deferred target with no trigger and no demand remains unloaded.
  Forgetting a loading path is not an input error under this policy.

## Acceptance and Implementation Evidence

The project owner explicitly approved loading triggerless deferred targets only
on prerequisite or manual demand in the review recorded by the linked discussion.
This acceptance does not rely on the existence of the prototype or passing tests.

[tests/compiler.nix](../../tests/compiler.nix) verifies no startup demand and
empty trigger categories for a triggerless deferred target, including one used
as a deferred target's prerequisite. Native opt-tree cases in
[tests/runtime-plan.lua](../../tests/runtime-plan.lua) verify manual loading,
startup prerequisite loading, and first-command prerequisite loading.

Public trigger names and omitted/single/multiple representations, matching and
first-trigger handoff details, repeated-definition normalization, and stable
manual group references remain separate review questions.
