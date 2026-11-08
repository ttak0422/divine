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
- Provide a per-definition opt-in with a VimEnter fallback that supplements native
  startup scanning. This was the previous implementation; startup config preceded
  after/plugin completion.
- Isolate opted-in after/plugin files in the generated runtime and source their
  originals synchronously before config at both startup and deferred load time.

## Decision Outcome

Proposed option: explicit `loadAfter = true` with uniform synchronous timing.
The bundle creates an opt runtime view that links package content except for
`after/plugin`. The original package derivation and output stay unchanged.
After ordinary unit loads, the runtime sources opted-in original after/plugin
scripts before configuration, at startup as well as during deferred loading.
This replaces the VimEnter fallback and also covers initial-buffer FileType,
command-line loading and disabled native plugin scanning.

Canonical source history and attempted-file tracking prevent repeating earlier
sources, including symlink aliases and files that threw. An after-script error
fails the unit immediately, skips remaining configuration and is retained without
retry. Startup setup propagates such a failure; there is no delayed failure after
configuration has already run.

Only after/plugin is hidden. Filetype, indent, syntax and other runtime assets
remain available through native lookup. Late after/ftdetect is sourced when
detection is already initialized, otherwise native initialization discovers it.
This registers rules without redetecting buffers. runtimePaths ordinary entries
precede after entries and are not isolated by the per-package opt-in.

### Consequences

- Positive: existing configurations retain default packadd behavior. Explicit
  opt-in works for packages such as cmp-buffer without an external loader.
- Positive: config and first-trigger handoff follow successful after/plugin work
  regardless of load time, without a later native scan repeating managed files.
  Late detection rules can be registered without sourcing unrelated after files.
- Negative: the generated view differs from the original package layout. Scripts
  are sourced from the original output path; plugins that infer sibling paths
  from script filenames or expect after/plugin in runtimepath need compatibility
  checks. Adding original package paths through another loader bypasses isolation.
- Negative: ordinary unguarded plugin scripts can still run again during native
  startup scanning. Source history cannot report earlier custom/native source
  failures to divine's unit state. Native reloads and arbitrary custom Lua
  execution remain outside the deduplication guarantee. There is no rollback or
  automatic retry.

## Implementation evidence and review

See [runtime behavior and limits](../runtime.md#after-directories),
[isolated runtime cases](../../tests/after.lua),
[actual startup checks](../../tests/after-startup.lua), and
[compiled real-plugin checks](../../tests/after-bundle.nix).
The exact option name, startup timing contract, and scope remain under review.
