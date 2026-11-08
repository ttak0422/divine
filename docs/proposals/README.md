# Remaining policy reviews

These are draft review proposals for the unchecked implementation tasks, not
accepted decisions. The existing runtime and compiler remain unchanged. New
characterization tests describe the current repeated-definition policy without
adopting it.

## Scope and existing work

The starting point is main at
[`93c9499`](https://github.com/ttak0422/divine/commit/93c9499701cfa5f9dc90ab229dcb75a3bdc56fc2),
after startup-demand and real-plugin event checks were merged in
[PR #13](https://github.com/ttak0422/divine/pull/13) and
[PR #12](https://github.com/ttak0422/divine/pull/12).

[PR #14](https://github.com/ttak0422/divine/pull/14) already covers the approved
normalization of equivalent repeated trigger forms. This review neither
reimplements it nor assumes it has merged. The remaining repeated-definition
policies are still distinct decisions.

## Decisions prepared for review

- **API:** [names, recursive schema and configuration references](api-and-triggers.md).
- **TRIGGER-POLICY:** [representations, matching and first-trigger handoff](api-and-triggers.md).
- **REPEATED-DEFINITIONS:** [complementary fields, edge/tool unions and provenance](repeated-definitions.md).
- **NATIVE-STARTUP:** [ordinary repeated scanning and possible explicit alternatives](native-startup.md).

Each proposal separates current behavior, examples, alternatives, a recommendation
and the remaining owner decision. No unchecked TODO becomes complete just by
opening or merging this review. Accepting a recommendation requires explicit
project review and an appropriate ADR status/update with that review linked.

Other implemented but proposed ADRs, such as SCC extraction and phase ordering,
retain their own review status. This queue does not adopt them indirectly.
