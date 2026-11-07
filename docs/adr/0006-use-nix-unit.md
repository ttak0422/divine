---
status: accepted
date: 2026-11-07
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Use nix-unit for Nix logic tests

## Context and Problem Statement

divine implements graph resolution and configuration compilation in Nix. Tests
need to identify individual cases, compare expected values and detect expected
and unexpected evaluation failures. The previous default Make target evaluated
a function without applying it and could report success without running tests.
The user selected nix-unit during implementation on 2026-11-07.

## Considered Options

- Keep direct assertions and repair the execution wrapper.
- Use nixpkgs `lib.debug.runTests` with explicit failure-to-exit conversion.
- Use nix-unit for named value and exception tests.

These approaches were compared before selection. Snapshot tests and flake checks
serve different purposes; neither replaces the evaluation runner. No snapshot
framework or NixOS VM framework is selected here.

## Decision Outcome

Chosen option: nix-unit, matching the user's choice to test logic written in Nix
with named cases and native expected-error support. Keep flake checks as the
build/execution entry point and headless Neovim for runtime behavior.

Use `pkgs.nix-unit` from the nixpkgs revision selected by
[flake.lock](../../flake.lock), without adding an independent input. The package
selection in [flake.nix](../../flake.nix) and the locked nixpkgs definitions
determine nix-unit and its evaluator versions; this decision does not pin a
separate release. The package's embedded evaluator is distinct from the host's
Nix or Lix CLI/daemon. No host daemon change is required; Lix-linked nix-unit has
not been validated.

### Consequences

- Positive: Individual input, resolver and compiler cases report their names;
  expected input errors use `expectedError` instead of swallowed exceptions.
- Positive: Both developer and CI execution use the same suite, with guards for
  discovered case names and deliberate mismatch/unexpected-error failures.
- Negative: nix-unit adds a binary and an evaluator-version compatibility
  dependency. The nixpkgs pin must retain a working nix-unit build.
- Negative: The Nix suite now runs inside a check derivation. `flake check
  --no-build` only evaluates that derivation; it no longer executes the suite.

## Implementation and Verification

At adoption, [tests/default.nix](../../tests/default.nix) discovered 10 input,
27 resolver and 14 compiler cases. A 52nd case verified every expected name, because an empty
nix-unit suite can otherwise succeed. [tests/nix-unit-runner.sh](../../tests/nix-unit-runner.sh)
requires successful cases to pass and named deliberate failures to exit nonzero.

The flake check imports pinned nixpkgs/lib directly and uses a private evaluation
store, retaining derivation-context tests without host daemon access or recursive
flake fetching. Default and explicit-library Make invocations, and the Darwin
sandbox derivation, passed all 52 cases and runner guards. Linux CI execution is
reported in the PR. This test-method acceptance does not accept any other
proposed identity, timing, SCC sequencing or trigger decision.
