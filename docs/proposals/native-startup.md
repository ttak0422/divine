# Review native startup rescanning

Status: proposed for owner review. This document does not change runtime behavior,
accept ADR 0005 or ADR 0008, or mark `NATIVE-STARTUP` complete.

## Question and recommendation

The remaining [NATIVE-STARTUP task](../../TODO.md) asks whether ordinary repeated
native scanning of unguarded plugin scripts needs a future explicit alternative.
The current behavior is intentional in the implementation and covered by a bundle
fixture, but that does not establish acceptance of a new startup policy.

**Recommendation for review:** keep ordinary native startup scanning as the
compatibility default. Do not infer a new once-only guarantee from controller
idempotence or from `loadAfter`. If an affected plugin warrants a separate mode,
first agree its scope and compatibility tests in a follow-up proposal. No new
option name or implementation is selected here.

The owner can either accept the documented boundary as sufficient and close this
review task, or keep it open with a concrete requirement for an explicit
alternative. Neither outcome is assumed by this draft.

## Current behavior

The [placement and timing contract](../design.md#placement-and-configuration-timing)
keeps startup targets in `opt` and explicitly loads them during init. Moving them
to `start`, postponing their configuration until `VimEnter`, or sourcing all
`after/` directories would change that contract.

The current [controller](../../lua/divine/init.lua) performs the following work
for a requested SCC after its prerequisite units have loaded:

1. Prepare each physical member with `packadd!`, making runtime paths and peer
   Lua modules available without sourcing its ordinary plugin scripts.
2. Remove the unit's trigger stubs and run its `preConfig` callbacks.
3. Run ordinary `packadd`, or the explicit `load` replacement, for physical
   packages not already loaded by this controller.
4. Run explicit `loadAfter` work, if requested.
5. Run the unit's `config` callbacks and retain its successful state.

These are the phases proposed in [ADR 0005](../adr/0005-scc-runtime-phases.md),
with the explicit after-directory phase proposed in
[ADR 0008](../adr/0008-opt-in-after-loading.md). They apply to startup and deferred
loads. `preConfig` and `config` become the internal `before` and `after` callbacks
in the [compiler](../../lib/compile.nix); an internal callback named `after` is
not an `after/plugin` script.

With normal plugin loading enabled, Neovim subsequently scans runtime plugin
scripts in its native startup phase. A package made visible and sourced by an
earlier `packadd` can be visited again. An unguarded `plugin/*.lua` or
`plugin/*.vim` script can therefore repeat its effects **after `config` has
already run**. A plugin's own loaded guard can prevent repeated effects, but
divine does not add such a guard to arbitrary plugin code.

This second scan does not repeat divine's load or configuration callbacks. The
controller's loaded-package and loaded-unit state only prevents repeated loads
through that controller, including shared dependencies and overlapping package
groups. It does not suppress Neovim's native scans or explicit external sourcing.
A native script error is not automatically converted into a retained controller
failure. Controller-managed failures still remain failed, without rollback or
automatic retry.

The relevant boundary is whether the package was loaded before a native scan,
not just its `lazy` declaration. A deferred prerequisite may be demanded during
init by a startup target ([ADR 0004](../adr/0004-startup-demand.md)); a trigger may
also fire early. Conversely, a target first loaded after the ordinary startup
scan does not encounter that already-completed scan. `lazy = true` alone is not
a general deduplication remedy.

See [ordinary startup scanning](../runtime.md#ordinary-startup-scanning-is-a-separate-phase)
for the current runtime contract.

## Why `loadAfter` is a separate question

Without `loadAfter`, `config` follows the ordinary load operation; it does not
promise that native `after/plugin` has finished. For an init-loaded default
package, native startup can source `after/plugin` later. A package first loaded
after startup does not get that phase from ordinary `packadd`.

With `loadAfter = true`, the [bundle builder](../../lib/bundle.nix) hides only the
package's `after/plugin` directory in the generated opt view. The controller
sources the original after-plugin scripts synchronously before `config`, both
during init and on deferred loads. Canonical source history and attempted-file
tracking in [after.lua](../../lua/divine/after.lua) limit repeated managed
sources, including symlink aliases and failed attempts.

Ordinary `plugin` scripts remain visible in that view. Consequently, enabling
`loadAfter` does **not** prevent their native startup rescan. It also does not
isolate user-supplied `runtimePaths` or stop another loader from adding the
original package path. `after/ftdetect` has its own initialization handling;
`after/ftplugin`, `after/indent`, `after/syntax` and other runtime assets retain
native lookup semantics. This proposal does not extend or replace those rules.

### Concrete current-API examples

Let `a` be the package fixture defined in [tests/bundle.nix](../../tests/bundle.nix).
Its guarded `plugin/a.lua` sets `vim.g.divine_a` once; its unguarded
`plugin/native-scan.lua` increments `vim.g.divine_native_scans` every time it is
sourced; its `after/plugin/a.lua` increments `vim.g.divine_a_after`.

This configuration fragment uses the existing provisional API:

```nix
{
  plugins = [
    {
      plugin = a;
      preConfig = # lua
        ''
          assert(not vim.g.divine_native_scans)
        '';
      config = # lua
        ''
          assert(vim.g.divine_native_scans == 1)
          assert(not vim.g.divine_a_after)
        '';
    }
  ];
}
```

For this isolated fixture under normal startup, the native phase later leaves
`divine_native_scans == 2` and `divine_a_after == 1`. The guarded `divine_a`
remains `1`. This is why before/after configuration around the managed load does
not mean before/after every later native source. The existing bundle test asserts
the final counts; the fragment above illustrates the earlier callback boundary.

For the same fixture, opting in changes only the after-directory boundary:

```nix
{
  plugins = [
    {
      plugin = a;
      loadAfter = true;
      config = # lua
        ''
          assert(vim.g.divine_native_scans == 1)
          assert(vim.g.divine_a_after == 1)
        '';
    }
  ];
}
```

The implementation still exposes `plugin/native-scan.lua` to native startup,
while hiding `after/plugin/a.lua` from that scan. Its expected final counts are
therefore `2` and `1`, respectively. This combined illustrative variant is not a
new executed regression test: the existing tests below separately assert the
ordinary rescan and the isolated after-directory behavior.

A custom `load` callback is already available, but replaces only step 3 above.
It cannot, by itself, promise suppression of a later native scan: common
`packadd!` preparation has already made the package runtime visible. The current
API has no per-target ordinary-plugin isolation option.

## Options for this review

These are candidates for this review, not a record that alternatives have
already been adopted, rejected or benchmarked.

1. **Keep native scanning and document the boundary.** Preserve existing package
   visibility, native integration and startup/deferred callback timing. Plugin
   guards remain responsible for avoiding repeated native effects. The cost is
   that unguarded scripts can repeat side effects after divine configuration;
   controller idempotence cannot be advertised as universal script idempotence.
   This is the recommended compatibility choice for the current default.
2. **Investigate an explicit managed-package alternative.** A possible design
   would isolate ordinary plugin scripts as well as explicitly source them at the
   existing load point. This would require a separate decision on interaction with
   `packadd`, custom `load`, source paths, native ordering, source failures, shared
   outputs and unmanaged loaders. The current after-only view is not evidence
   that such a design preserves arbitrary plugin compatibility. No field or
   implementation is proposed as ready in this draft.
3. **Disable the global native plugin scan or postpone managed startup loads.**
   Disabling scanning affects unmanaged plugins and default native after-plugin
   behavior, not just divine's unguarded scripts. Postponement would move startup
   configuration and plugin availability across native phases and initial-buffer
   events. Neither is recommended as a default change or a transparent fix under
   the current timing contract. Existing `--noplugin` fixtures exercise an input
   condition; they do not endorse a new divine-wide suppression policy.

## Existing evidence and limits

The following describes assertions inspected in the repository, not tests rerun
for this documentation change:

- [tests/bundle.nix](../../tests/bundle.nix) creates guarded and unguarded ordinary
  plugin scripts and default after-plugin scripts. [tests/bundle.lua](../../tests/bundle.lua)
  requires an unguarded ordinary count of exactly `2`, guarded counts of `1`, a
  native startup after-plugin count of `1`, and no default after-plugin execution
  for the deferred package loaded by its command. The
  [flake bundle check](../../flake.nix) launches this generated init in a fresh
  Neovim with ordinary plugin scanning enabled.
- [tests/runtime-plan.lua](../../tests/runtime-plan.lua) checks controller phase
  ordering, shared-package deduplication, retained failures and SCC peer-module
  preparation. Its isolated/RPC cases do not reproduce a fresh process's later
  native startup scan.
- [tests/after-startup.lua](../../tests/after-startup.lua) launches fresh processes
  for native scanning, `--noplugin`, initial FileType, late `-c` loading, nested
  events and retained after-script failures. It asserts opted-in after scripts
  finish before config without later repetition, while default packages keep
  native timing.
- [tests/after-bundle.nix](../../tests/after-bundle.nix) checks the generated opt
  view, preserved ordinary plugin and other runtime files, initial-file behavior
  and one real cmp-buffer source registration before config in startup and
  deferred bundles. This is focused after-directory compatibility evidence, not
  ordinary-script isolation or general plugin compatibility evidence.

Nix and Neovim are unavailable in the environment used to prepare this draft.
No `make test`, bundle build or runtime execution was performed here. See
[verification scope](../runtime.md#verification-scope) for the repository's wider
fixture coverage and limitations.

## Owner decisions and follow-up acceptance criteria

- Is preserving native rescanning an accepted compatibility boundary, sufficient
  to close `NATIVE-STARTUP`, or is a future explicit mode required?
- If an alternative is required, which concrete plugin and repeat side effect
  justify it? Must it preserve the current before/load/after timing and coexist
  with unmanaged runtime trees and existing custom `load` callbacks?
- Should the guarantee cover only divine-managed ordinary plugin sources, or
  include external native/custom sources? The latter is not guaranteed today
  and needs an explicit feasibility and ownership boundary.

For the unchanged-default choice, acceptance should record the owner decision
and keep the native twice-scan fixture as compatibility evidence. It must not
silently accept unrelated proposed ADRs or public API names.

Before implementing an alternative, agree tests for guarded/unguarded Lua and
Vimscript, ordinary and after-plugin counts before config and after startup,
initial-file and early-trigger timing, deferred loads after startup, SCC/shared
packages, custom load functions, synchronous failure retention, and coexistence
with unmanaged runtime paths. Test preserved filetype/runtime assets and a
concrete affected real plugin in addition to isolated counters. Keep a separate
unchanged-default case, and report actual commands/results rather than treating
these proposed criteria as existing coverage.
