# Executable runtime prototype

The compiler, bundle and runtime connect the existing graph to Neovim. These are
provisional implementation interfaces, not accepted public API decisions.
[0005](adr/0005-scc-runtime-phases.md) records SCC sequencing, and
[0008](adr/0008-opt-in-after-loading.md) records after-directory handling.
The behavior boundaries in [design.md](design.md) still apply.

## Compile and build

`lib.compile configuration` produces a graph, a runtime plan and its Lua text.
`lib.mkBundle { pkgs = ...; configuration = ...; }` builds a directory containing
`init.lua`, `plan.lua`, the Lua runtime and `pack/divine/opt` entries. The full
output-path hash names each entry, so equal package display names do not collide.
Default entries link directly to package outputs. For `loadAfter = true`, a
symlink view omits only `after/plugin` from native runtime scanning; the runtime
sources those files explicitly from the unchanged original output.
No package is promoted into `start`, and no external loader or wrapper is used.
Only explicitly declared configuration dependencies are placed; a package's
`dependencies` metadata is not interpreted as a second dependency graph. This is
an explicit requirement, not an instruction to remove dependency attributes from
the derivation. The original package output and its build/check inputs remain
unchanged. Required runtime plugins must be declared in `dependPlugins` even if
nixpkgs also lists them; recursive `extraPackages` remains independent.

In the pinned nixpkgs, [vimUtils.packDir](https://github.com/NixOS/nixpkgs/blob/0bb2eedc20e4739f29e8045034f2828ad7054f8f/pkgs/applications/editors/vim/plugins/utils/vim-utils.nix#L160-L224)
recursively expands `dependencies` and
places dependencies of opt plugins in `start` unless the same outputs are already
in opt. An explicitly selected variant can therefore coexist with the original
implicit dependency. Divine does not use that packaging helper. Its direct opt
entries enforce this boundary without rebuilding or stripping package outputs.
Neovim itself does not interpret Nix dependency attributes.

This does not remove plugins injected by an independently configured Neovim
wrapper, another packpath or a plugin's own loader. Avoid separately installing
the same managed plugins through such a wrapper. The ordinary native startup
rescan described below is also separate from dependency expansion.

The bundle can be used with `nvim -u /path/to/bundle/init.lua`. Its init entry adds
the bundle to runtimepath and packpath, prepends all recursively collected
`extraPackages` binaries to PATH, registers non-key triggers, executes common startup
configuration, loads startup units, then installs remaining key triggers and
handles already-open filetypes. This lets startup configuration set mapleader
before lazy keys are expanded, while require/command triggers already work.
`runtimePaths` accepts paths or package outputs for additional runtime trees;
ordinary trees are added before the after section, and existing `after`
subdirectories are appended in declaration order. This keeps a later ordinary
tree from overriding an earlier after tree. Existing paths are not duplicated.
It does not source an entire `after` directory.

The `lazy` option defaults to `false`, including package shorthand and recursive
detailed definitions. The resolver applies this default after merging repeated
occurrences, so an explicit `lazy = true` elsewhere still requests deferred
loading without conflicting with shorthand. Conflicting explicit booleans remain
errors. Trigger fields do not imply deferred loading; set `lazy = true` explicitly.
A dependency with omitted timing loads at startup even when its parent is deferred.
A lazy node without triggers is not loaded automatically unless another
startup or triggered node needs it as a prerequisite; it also remains available
through the returned controller's manual `load(node_id)` operation.

When updating a configuration that relied on the previous deferred default,
add `lazy = true` to each plugin that should remain deferred, including any
otherwise eager dependencies. Retain existing triggers; do not add flags to
everyday editing plugins that should now load at startup.

Supported provisional fields are `lazy`, `preConfig`, `config`, `load`,
`loadAfter`, `onEvents`, `onCommands`, `onFiletypes`, `onKeys`, and `onModules` in each definition;
`startupConfig` and `runtimePaths` are root metadata. Unknown fields fail instead
of being silently ignored. `preConfig`, `config` and `startupConfig` accept Lua
text or a path to a Lua source file. Optional `load` is a Lua function body with
`name` as its argument; it replaces only the ordinary load phase, not SCC runtime
preparation. Inline Nix strings annotated with `# lua` remain the documentation
convention.

## SCC loading and failure states

For each requested unit, the runtime first loads prerequisite units. It then:

1. Runs `packadd!` for every member to make every runtime available.
2. Removes that unit's trigger stubs.
3. Runs all member `preConfig` callbacks.
4. Runs ordinary `packadd` (or each explicit replacement load function).
5. Processes explicit `loadAfter` work, if any, as described below.
6. Runs all member `config` callbacks.

The deterministic member order is provisional and is not a dependency order
inside the cycle. Preparation precedes all callbacks, so a pre-load callback can
require a peer's Lua module without requiring that peer's plugin script to have
already executed. Reentry after preparation returns without recursively loading
the unit. Reentry before preparation fails.

Successful units load once through the controller. A failure is retained as a
failed unit and is rethrown rather than retrying partly executed callbacks or
plugin scripts. No rollback, unload or hot reload is claimed.

The internal `setup(plan)` entry consumes compiler-produced plans, not human
configuration. Nix validates configuration and constructs the node records,
unique package names, callback wrappers, SCC membership, acyclic dependencies
and startup-unit references. The runtime indexes those units without repeating
structural validation. Handwritten or mutated plans must satisfy the compiler
contract; they are not a separately validated input interface. Manual controller
`load(node_id)` and `load_unit(unit_id)` calls still reject unknown identifiers,
and runtime reentry and retained-failure checks remain necessary. Trigger checks
for Neovim events, command/key conflicts and other runtime conditions also remain.
Lua source syntax and callback execution can still fail at runtime; compilation
does not prove user code correct.

### Ordinary startup scanning is a separate phase

Ordinary `packadd` during init executes plugin scripts immediately. With normal
plugin loading enabled, Neovim's later runtime scan can execute an **unguarded**
script again. Many real plugins use their own loaded guards. The runtime does not
suppress Neovim's global plugin phase or claim that it can make arbitrary plugin
scripts idempotent. The bundle fixture checks both guarded scripts and this
unguarded native behavior explicitly. Load callbacks themselves are not repeated.

The native startup `after/plugin` phase still runs for default packages and
unmanaged runtime trees. Default configuration executes before that later phase,
and deferred loading after startup does not source `after/plugin` by default.
The explicit mechanism below isolates opted-in `after/plugin` files and sources
them before configuration at either load time. `after/ftplugin` belongs to the
separate FileType path.

## After directories

`config` is a Lua callback after the load operation, not an `after/` directory.
The provisional per-definition `loadAfter = true` explicitly opts into loading
package `after/plugin` and late `after/ftdetect` scripts. It works at roots and
recursive dependencies, with startup or deferred targets, and with an explicit
`load` callback. Omission leaves the existing native `packadd` behavior unchanged.
Repeated definitions use the existing equality/conflict policy: omission does
not conflict with `true`, but explicit `true` and `false` do.

```nix
{
  plugin = pkgs.vimPlugins.cmp-buffer;
  lazy = true;
  loadAfter = true;
  onEvents = "InsertEnter";
  dependPlugins = [ pkgs.vimPlugins.nvim-cmp ];
}
```

This registers cmp-buffer's source from its `after/plugin` script. Configure
nvim-cmp separately as needed; this example only demonstrates loading.

- **Startup and deferred loading:** source each opted-in member's original
  `after/plugin/**/*.vim`, then `*.lua`, in member/directory order after all
  ordinary unit loads and before any `config` callback. Nested files are included.
  The generated opt view excludes only these files from native scanning, so the
  later startup scan does not repeat them. This same synchronous sequence applies
  during init, initial-buffer FileType loading, `-c` commands and `--noplugin`.
  There is no VimEnter fallback and no batch source of other after directories.
  Config and the first-trigger handoff can depend on successful after/plugin
  completion. Event-triggered loading allows nested events emitted by scripts;
  the runtime's reservation and reentry guards prevent recursive unit loads.
- **after/ftdetect:** when filetype detection is already initialized, source the
  direct `*.vim` and `*.lua` files in the native `filetypedetect` group. Otherwise,
  leave them for the later native initialization scan. This registers detection
  rules; it does not redetect existing buffers or invent a FileType event.
- **after/ftplugin, after/indent, after/syntax:** keep native runtime lookup and
  the existing FileType replay, without requiring `loadAfter`. These scripts run
  for matching buffers, not once per plugin. Enable the corresponding native
  filetype/indent/syntax facilities. Other runtime assets, such as after/queries,
  remain available to the subsystem that reads them; no generic execution is
  inferred from the directory name.

`runtimePaths = [ ./runtime ];` is the way to provide a user-owned runtime tree,
for example `runtime/after/ftplugin/lua.lua`, `runtime/after/indent/lua.lua`, or
`runtime/after/ftdetect/custom.vim`. These trees are present from init and follow
native scanning; the package opt-in does not manually source their files.

Canonical source paths deduplicate earlier `:source` operations, including
symlink aliases and native sources from independently added runtime paths.
Attempted files are not retried after partial
failure. Arbitrary user `dofile`, custom loader internals, explicit later
`:runtime!` or multiple independently configured loaders are outside that
exactly-once guarantee. As before, ordinary `plugin` scripts can be rescanned by
Neovim during startup.

An after-script error fails its unit synchronously and skips its remaining
configuration, at startup as well as after startup. The retained failure is
re-thrown on later loads; partial effects are not undone. Independent units can
still be loaded explicitly, but a startup load failure propagates out of setup
rather than silently continuing the startup list. Source history cannot
distinguish an earlier custom/native source that failed from one that succeeded,
so divine does not claim to retain those external errors in controller state.

The generated view changes the visible package layout only for opted-in outputs.
Managed after/plugin scripts are sourced by their original output path, not their
view path. Plugins that locate sibling files from their script filename, compare
runtime paths, or expect their own after/plugin directory to be discoverable
through runtimepath may need compatibility checks. Manually adding the original
package to runtimepath, or using a custom loader that does so, bypasses isolation
and can reintroduce native startup duplication. Do not install the same package
through another wrapper or loader. No general plugin-compatibility guarantee is
implied by the focused fixtures.

## Trigger handoff

String triggers accept either one string or a list; omission and empty lists
mean no trigger of that kind. These are prototype representations, not final
schema choices.

- `onEvents`: native Neovim event names, including aliases and case variants.
  The Nix compiler normalizes case and aliases, deduplicates each node's events,
  and rejects unknown names using Neovim 0.12.4's event catalog (the nixpkgs
  `nixos-26.05` default). Plans contain callback spellings such as `BufReadPost`,
  not the shorter `BufRead` alias. Aliases share one dispatcher and each pending
  target is loaded at most once per batch. Runtime registration creates no
  temporary normalization autocmds. The runtime still rejects events unavailable
  in the running Neovim before installing any triggers. Other versions may work
  when they support the plan's canonical events; newer-only names require an
  explicit catalog update. Handwritten runtime plans must use canonical names.
  `lib/events.nix` records the upstream source; `checks.<system>.events` verifies
  the catalog's identities and compiled alias/case plans against Neovim.
  `events-stable` also checks the full catalog against the stable source.
  The stable test input is separate from the existing development nixpkgs input.
  Matching pending units are loaded together,
  then the event is dispatched through Neovim in each eligible named augroup.
  Groups with any handler for that event before loading are excluded, even when
  the old handler's pattern does not match. Ungrouped handlers are excluded too.
  Adding a handler to an existing event group does not replay it on the first
  trigger; use a new event group when first-trigger handoff is needed.
- `onCommands`: full user-command names. The stub loads before invocation and
  forwards arguments, bang, range and modifiers. Completion also loads the target
  and delegates to the newly installed command.
- `onFiletypes`: exact filetype names. Matching current and subsequently opened
  buffers can load the unit. FileType is dispatched globally after loading, so
  existing and ungrouped FileType handlers also run again. The native filetype
  loader handles ftplugin and after/ftplugin; no manual source pass is added.
- `onKeys`: a key string (normal mode), `{ lhs = "..."; mode = "n"; }`, or a list
  of either. The original operation is fed back after loading; normal-mode count
  and register handling are tested, along with insert and visual operations.
  Operator-pending keys (`mode = "o"`) load through an expression mapping and
  hand the key back without leaving the pending operation. The first invocation
  is compared with loaded/native mappings for `d`, `g~`, forced linewise `dV`,
  operator/motion counts and named registers.
  Loading an operator-pending target runs under Neovim's `textlock`: configuration
  and plugin scripts must not edit buffers, move the cursor or switch windows
  during that load. Buffer edits raise `E565`; the unit retains the failure,
  removes its trigger stubs, reports the error and cancels the pending operator.
  It does not replay the key or retry automatically.
  Partial configuration effects are not rolled back. Load such targets at
  startup instead, or defer nonessential edits explicitly (deferred work runs
  after the pending operation, not before its motion).
  Select-mode expression mappings preserve character, line and block selections
  across first and repeated invocations, compared with native mappings. Terminal
  expression mappings preserve terminal mode and deliver the same input bytes on
  first and repeated invocations through an in-process terminal channel. This
  verifies terminal mapping handoff, not shell or external terminal-program behavior.
- `onModules`: exact Lua module names or dotted namespace prefixes. `foo` matches
  `foo` and `foo.bar`, not `foobar`. The existing Lua searcher chain resumes after
  preparation. Matching plugin names is never substituted for module names.

Duplicate command/key ownership and existing command/key conflicts fail rather
than replacing unrelated user definitions. Events may demand several units.
Event and current-filetype batches stop at the first load failure without
replaying that batch. Targets not yet attempted retain their triggers, so an
independent target can load on a later trigger. This is not retry of a failed
unit: failed units still retain and rethrow their original error. Pending batch
targets are reserved against nested event dispatch, and targets already loaded
as dependencies or SCC peers are skipped.
Key conflicts are checked as a batch after startup configuration, before any key
stubs are installed. This avoids binding a stale mapleader, but means a conflict
can be reported after startup callbacks have run. Further real-plugin event
semantics coverage is tracked in [TODO.md](../TODO.md).

BufReadPost first dispatches BufReadPre; FileType first dispatches BufReadPre
and BufReadPost. Each supplemental event excludes its own pre-load groups and
uses the triggering buffer's name for native matching. These are synthetic
notifications after loading, not a second read of the file or a recreation of
its original read-time state.

Dispatch runs in the original buffer with the original event match and data.
Supplemental events also receive the data. Neovim owns pattern matching, callback
identity, `once`/`++once`, callback-return removal, nesting and Vimscript context;
handlers are not copied or manually deleted. The native API derives event fields
such as `<afile>` rather than overriding callback arguments. A same-event guard
prevents trigger recursion during loading and replay. This does not suppress
plugin handlers' own native nested events.

FileType replay deliberately repeats existing handlers. A native handler still
pending in the outer dispatch may run again after the replay; handlers should be
idempotent. Group-level replay does not promise original global registration
order across groups or universal first-event equivalence. The excluded-group and
ungrouped rules apply to ordinary and supplemental events, not to FileType.

## Verification scope

Named nix-unit cases cover compilation as well as graph resolution. The
existing headless runtime check now runs isolated primitives, real opt/SCC
fixtures and native trigger fixtures. The bundle build check starts a fresh
Neovim with generated init, validates opt layout, startup/configuration phases,
command and module handoff, native after/plugin behavior and an external tool.
The `nixpkgs-dependencies` check separately uses the pinned real
`vim-textobj-entire`, `vim-textobj-line` and their shared `vim-textobj-user`.
It reproduces two discoverable dependency outputs with nixpkgs' packDir and an
explicitly selected variant, then verifies divine excludes implicit dependencies,
loads only the selected shared dependency, preserves the original parent
derivation, and keeps a nested external tool. Actual entire-buffer and deferred
line text-object operations run in fresh Neovim processes. The reference checks
duplicate runtime candidates, not a claim that guarded plugin code always
executes twice. This focused regression is not a broad third-party compatibility
suite.
The selected nix-unit method is recorded separately in
[ADR 0006](adr/0006-use-nix-unit.md). Adopting the test method does not accept the
proposed runtime behavior asserted by its fixtures.

The after-directory checks add native startup, late `-c` and initial FileType
loading, disabled native plugin scanning, synchronous retained failures, Lua/Vim
ordering, source aliases and filetype overrides. `checks.<system>.after-bundle`
builds real nvim-cmp/cmp-buffer bundles and verifies exactly one buffer-source
registration inside config at startup and after startup, alongside runtimePaths
ordering, initial-file overrides, after/ftdetect and generated-view preservation
of other runtime assets. This is focused coverage, not a general completion-plugin claim.

For overlapping explicit package groups, reentry into a different group while a
shared package's ordinary loader is still running fails rather than reporting
premature configuration success. Reentry into the same already-prepared unit
retains the existing SCC behavior. Physical load failures remain sticky across
overlapping units; ordinary configuration failures belong to their own unit.
