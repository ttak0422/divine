---
status: accepted
date: 2026-11-07
discussion: "https://github.com/ttak0422/divine/pull/1"
---

# Use mini.test for Lua behavior tests

## Context and Problem Statement

The Lua load primitive, runtime plan and native-trigger suites previously ran as
three assertion scripts. Their scenarios shared editor state and reported only
script-level outcomes. The user selected introducing mini.test on 2026-11-07.
Tests need named results, reliable failure exits and isolated setup/cleanup,
without changing the real Neovim startup behavior under test.

## Considered Options

- Retain the direct assertion scripts.
- Use mini.test for named Lua cases and isolated child Neovim processes.

No broader test-framework comparison or snapshot framework is adopted here.

## Decision Outcome

Chosen option: mini.test, following the user's selection. Use
`pkgs.vimPlugins.mini-test` from the existing nixpkgs lock (0.18.0), only in the
development shell and the runtime check. Do not add another flake input or place
the framework in generated bundles or user runtime paths.

Use mini.test sets with per-case setup and cleanup. Each case executes in a fresh
headless Neovim child without loading mini.test into that child. Keep the separate
generated-init bundle and real-plugin integration checks as plain headless
Neovim processes, preserving native startup and plugin loading phases.

This adopts the testing method only. It does not accept the other proposed
identity, timing, SCC sequencing, trigger handoff or public API choices.

### Consequences

- Positive: Every migrated scenario has a name, and failures identify the case
  rather than terminating a shared assertion script at its first failure.
- Positive: Fresh processes isolate globals, buffers, mappings, autocmds, module
  caches, package paths and stubs. Cleanup hooks remove temporary plugin trees
  even after assertions fail.
- Positive: The same entry point runs from Make and the flake check. Explicit
  case discovery and runner guards prevent empty suites or swallowed failures
  from making CI green.
- Negative: Starting one Neovim process per case costs more than sharing one
  process. RPC callbacks cannot capture host Lua upvalues; they use fixture
  arguments instead.
- Negative: The pinned mini.test and Neovim versions are development dependencies
  whose compatibility must be checked when updating nixpkgs.

## Implementation and Verification

[tests/cases.lua](../../tests/cases.lua) inventories 53 named cases: 6 primitive,
19 runtime-plan and 28 native-trigger cases. The migration preserves the previous
assertions and separates previously coupled scenarios. The real opt/SCC case
now runs without the trigger mock used by isolated plan cases.

[tests/run.lua](../../tests/run.lua) requires nonempty suites and verifies every
expected name before execution. It uses mini.test's stdout reporter for nonzero
case failures, Neovim's `-l` mode for collection/setup errors, and a scheduling
wait for asynchronous completion. This wait is not a hard timeout for a hung
synchronous child RPC. [tests/mini-test-runner.sh](../../tests/mini-test-runner.sh)
checks success, an intentional assertion failure, an empty suite, a collection
error and fixture cleanup after failure through this same entry point. Matching
failure messages prevent an unrelated startup failure from satisfying a guard.

Run `nix develop -c make test` and `nix flake check --print-build-logs` to execute
the suites and guards. `nix flake check --no-build --all-systems` only evaluates
check definitions. Platform-specific executed results are recorded in the PR;
this ADR does not claim broader plugin or Neovim-version compatibility.
