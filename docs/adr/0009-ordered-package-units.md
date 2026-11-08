---
status: proposed
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/11"
---

# Configure ordered packages as independent units

## Context and Problem Statement

A configuration may need several plugin scripts loaded in a declared order before
one shared config callback. A dependency edge describes prerequisites, not the
identity of that shared configuration. [ADR 0001](0001-output-path-identity.md)
accepts physical package output-path identity and finite back-references; it does
not decide configuration-unit identity or a multi-package interface.

## Considered Options

- Add `packages = [ a b ];` as an alternative to a single `plugin`, with ordered
  members and one shared configuration occurrence.

No comparative experiment or rejection of other interfaces is recorded.

## Decision Outcome

Proposed option: ordered package lists with independent configuration occurrences,
so one declaration can prepare several runtimes and configure them together
without merging its hooks with every other declaration of the same packages.

`packages` is a nonempty list of derivations, not nested definitions. Repeated
outputs retain their first position. Nested definitions remain in `dependPlugins`,
which accepts the same singleton or multi-package forms as roots. Each packages
occurrence has its own hooks, triggers, timing and metadata. Its internal identity
comes from its composed input location, not equality of member lists. Copying the
same definition creates another configuration occurrence. No stable public group
identifier or reference syntax is introduced.

Load prerequisite units first, prepare every member runtime, run shared preConfig
once, load each not-yet-loaded physical package in declaration order, source
opted-in after/plugin in that order, then run shared config once. Physical loads
are deduplicated by output path across the controller; overlapping groups retain
independent hooks. A group's custom load callback receives each not-yet-loaded
package's opt name. The first physical load wins, even when later configurations
supply another load callback. Ordinary native startup rescans remain outside this
controller guarantee.

Existing singleton shorthand, settings merging and finite SCC semantics remain.
A shorthand dependency or manual `load(package_path)` requests the legacy
singleton configuration, not every group containing that output. To request
shared group config as a dependency, include its full packages definition there.
Doing so at several locations creates several config occurrences, not a shared
reference; named test collisions still fail.

`loadAfter` is physical policy across overlapping declarations: `true` applies
whenever that package is loaded, omission is unspecified, and explicit true/false
conflicts fail. Its isolated runtime and synchronous timing are described in
[ADR 0008](0008-opt-in-after-loading.md). Group `test` shorthand is rejected because
there is no unique package-derived name; use `tests.<name>`.

### Consequences

- Positive: shared config has a clear boundary after ordered package loading,
  while physical package identity and existing singleton declarations remain.
- Negative: group order cannot undo an earlier load through another group or
  dependency. Independent hooks may still change shared plugin state.
- Negative: origin-derived IDs change when configuration composition changes;
  they are internal, unsuitable as durable user references. Copying a definition
  repeats its configuration rather than establishing shared identity.

## Implementation evidence and open questions

See [resolution](../resolution.md), [types](../nix-types.md), and
[runtime sequencing](../runtime.md). Public naming, occurrence identity,
first-load precedence and overlap policy remain review choices. Implementation
and passing checks do not accept this proposal or amend ADR 0001.
