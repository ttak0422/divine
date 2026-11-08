---
status: accepted
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/14"
---

# Normalize equivalent trigger forms before comparison

## Context and Problem Statement

Repeated singleton definitions compare their supplied fields in Nix before the
compiler creates runtime triggers. Previously, `onCommands = "Example"` and
`onCommands = [ "Example" ]` conflicted even though they compile to the same
trigger. The existing compiler also recognizes event aliases/case, default key
modes and repeated string conditions. Comparing raw forms makes composition
stricter than those established trigger meanings.

## Considered Options

- Retain exact raw typed comparison, including scalar versus list differences.
- Normalize equivalent trigger representations before comparing repeated fields,
  while rejecting other differences rather than choosing or combining values.

## Decision Outcome

Chosen option: "Normalize equivalent trigger representations before comparison",
because representation differences should not prevent composing equivalent
settings, while genuinely different settings need an explicit Nix-side choice.

For the five known trigger fields, build a canonical comparison view using the
same form rules as the compiler:

- String conditions accept a singleton or list. Events use the existing canonical
  native names, including their aliases and case variants. Commands, filetypes
  and module namespaces remain case-sensitive.
- Keys accept a string, a `{ lhs; mode?; }` record, or lists of these. A string and
  a record without `mode` mean normal mode. Different key modes or lhs values
  remain different; runtime leader expansion and key-notation interpretation are
  not performed in Nix.
- Repeated equal string conditions are removed in first-occurrence order. Key
  duplicates are retained because the runtime rejects duplicate bindings.
- Keep distinct-element order and Nix string build contexts. Reordered lists,
  subsets, different contexts, different Lua source/configuration or other
  unequal values are conflicts. Do not sort, union, concatenate or apply hidden
  precedence to resolve a conflict.

The resolver retains the first supplied raw setting and all current provenance;
normalization is a comparison view, not a new public graph representation.
Omitted fields stay omitted and do not supply empty trigger defaults. Explicit
empty lists still conflict with nonempty declarations. Only `lazy = null` retains
its existing special unspecified-timing meaning.

Raw resolution remains distinct from compiler input validation. A malformed raw
trigger falls back to strict comparison; it is not coerced into a valid value.
The compiler still validates supplied definitions and rejects malformed triggers.
Package-group occurrences remain independent and are not merged by this change.

### Consequences

- Positive: Equivalent scalar/list, event and key forms compose at any dependency
  depth without changing their runtime trigger meaning.
- Positive: Other differences still fail with the package, field and both input
  locations, so the user can compose a deliberate final value in Nix.
- Negative: Semantically unordered alternatives are not treated as sets; a
  different order still conflicts. Context differences remain significant even
  when the displayed string text matches.

## Acceptance and Implementation Evidence

The project owner explicitly approved normalizing semantically equal trigger
representations before comparison and rejecting other different specifications.
This acceptance does not adopt public field names or all remaining composition
policies in [ADR 0002](0002-repeated-definitions.md). Complementary-field
composition, edge/tool unions and provenance policy remain separate review
questions; their current behavior is preserved.

[lib/trigger-forms.nix](../../lib/trigger-forms.nix) shares normalization between
[resolution](../../lib/resolve.nix) and [compilation](../../lib/compile.nix).
The comparison path deduplicates strings with context-sensitive equality, and
event spelling normalization preserves the original build context.
[tests/trigger-normalization.nix](../../tests/trigger-normalization.nix) covers
both entry points, nested definitions, aliases/defaults, order and value
conflicts, string contexts, malformed raw inputs, provenance and independent
groups. Public matching/handoff and manual group-reference APIs remain outside
this decision.
