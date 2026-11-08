---
status: proposed
date: 2026-11-08
discussion: "https://github.com/ttak0422/divine/pull/7"
---

# Supplement after directories through explicit opt-in

## Context and Problem Statement

The [design contract](../design.md#loading-behavior-for-after) preserves ordinary
packadd by default. It does not source a late opt package's after/plugin or
after/ftdetect scripts. Runtime assets such as ftplugin, indent and syntax use
different native lookup phases, so sourcing the entire after directory is not a
valid implementation. Startup already has a native after/plugin scan, and
manually sourcing scripts during init can duplicate side effects.

The user requested after-directory support on an independent implementation
branch. The implementation and names below are proposed, not accepted API.

## Considered Options

- Keep explicit per-target manual sourcing/custom load operations only.
- Provide a per-definition opt-in that supplements native directory-specific
  behavior without changing default loading.

## Decision Outcome

Proposed option: explicit `loadAfter = true`, because it removes repeated
per-plugin loader code while retaining the established default. It sources late
after/plugin scripts after ordinary unit loads and before configuration, and
registers after/ftdetect when detection is already initialized.

During startup, only after/plugin sourcing is deferred to a VimEnter fallback.
Normal loading and configuration remain synchronous. Canonical source history
prevents repeating files already sourced by the native scan, including scripts
that threw. The fallback covers initial-buffer and command-line loading that
occurs after the native scan but before VimEnter. Filetype, indent and syntax
continue to use native lookup; runtimePaths ordinary entries precede after
entries.

### Consequences

- Positive: existing configurations retain default packadd behavior. Explicit
  opt-in works for packages such as cmp-buffer without an external loader.
- Positive: startup scripts are not sourced twice by divine and the native scan;
  late detection rules can be registered without sourcing unrelated after files.
- Negative: during startup, config and first-trigger handoff precede after/plugin
  completion. The opt-in does not provide uniform post-after configuration timing.
- Negative: source history cannot report native source failures to divine's unit
  state. Native reloads and arbitrary custom Lua execution remain outside the
  deduplication guarantee. There is no rollback or automatic retry.

## Implementation evidence and review

See [runtime behavior and limits](../runtime.md#after-directories),
[isolated runtime cases](../../tests/after.lua),
[actual startup checks](../../tests/after-startup.lua), and
[compiled real-plugin checks](../../tests/after-bundle.nix).
The exact option name, startup timing contract, and scope remain under review.
