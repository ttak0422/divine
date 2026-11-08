---
status: accepted
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Use output-path identity for finite package back-references

## Context and Problem Statement

Roots and dependencies must accept the same recursively nested package shorthand
and detailed definitions. Cycles must form SCC load units. The package graph
needs an identity rule and a finite way to express back-references without
constructing directly cyclic Nix values.

This decision concerns package nodes within one resolved graph. It does not
choose the identity, grouping or public schema of reusable configuration units,
including a possible interface that groups multiple packages in one unit.

## Considered Options

- Package output-path identity, with package occurrences referring to detailed
  declarations elsewhere in the same finite input (existing implementation).
- Explicit configuration IDs if multiple configurations of the same output are
  needed (previously noted in [resolution.md](../resolution.md#identity-and-repeated-definitions)).
  Configuration-unit identity remains a separate API question; this decision
  neither implements that alternative nor rejects it for a future unit interface.

## Decision Outcome

Chosen option: "Package output-path identity with finite package references",
because it supports shared package nodes and finite cycles without an additional
package-reference field.

Within one resolved package graph, occurrences with the same output path refer
to one node. Distinct output paths remain distinct even when display names match.
Package values and their build contexts are retained; string context is removed
only from identifiers used as keys. A package occurrence can refer back to a
node described elsewhere in the finite input, including a self-reference.
Detailed definitions and recursive dependencies remain valid at every depth.
Directly cyclic Nix values are outside this finite-input contract.

Shorthand does not assign occurrence-level timing or configuration defaults. The
separately specified `lazy = false` default is applied after merging occurrences.
This decision does not accept the settings-equality, conflict, edge/tool-union or
provenance policies in [ADR 0002](0002-repeated-definitions.md). SCC extraction,
within-unit runtime ordering and startup-demand policies also remain separate.

### Consequences

- Positive: A finite input can describe shared nodes, cycles and self-dependencies
  while preserving detailed definitions and recursive dependencies at every depth.
- Negative: One package graph cannot distinguish multiple package nodes with the
  same output path. This is not a rule for the identity or number of reusable
  configuration units. Directly cyclic Nix values remain unsupported.

## Implementation Evidence and Remaining Questions

The existing implementation in [lib/resolve.nix](../../lib/resolve.nix) already
uses this rule. [tests/resolver.nix](../../tests/resolver.nix) covers shared nodes,
finite cycles, self-dependencies and distinct output paths;
[tests/definitions.nix](../../tests/definitions.nix) covers finite references
between separately declared definitions.
No runtime or resolver behavior changes are required by this decision.

Public names, configuration-unit identity and any multi-package input interface
remain open. Repeated-definition policies remain proposed in ADR 0002; accepting
package identity does not silently accept those policies.
