# Executable runtime prototype

The compiler, bundle and runtime connect the existing graph to Neovim. These are
provisional implementation interfaces, not accepted public API decisions. All
existing ADRs remain proposed; [0005](adr/0005-scc-runtime-phases.md) records the
new SCC sequencing choice. The behavior boundaries in [design.md](design.md)
still apply.

## Compile and build

`lib.compile configuration` produces a graph, a runtime plan and its Lua text.
`lib.mkBundle { pkgs = ...; configuration = ...; }` builds a directory containing
`init.lua`, `plan.lua`, the Lua runtime and `pack/divine/opt` symlinks. The full
output-path hash names each symlink, so equal package display names do not collide.
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
links already enforce this boundary without rebuilding or stripping packages.
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
existing `after` subdirectories are added separately. It does not source an
entire `after` directory.

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
`onEvents`, `onCommands`, `onFiletypes`, `onKeys`, and `onModules` in each definition;
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
5. Runs all member `config` callbacks.

The deterministic member order is provisional and is not a dependency order
inside the cycle. Preparation precedes all callbacks, so a pre-load callback can
require a peer's Lua module without requiring that peer's plugin script to have
already executed. Reentry after preparation returns without recursively loading
the unit. Reentry before preparation fails.

Successful units load once through the controller. A failure is retained as a
failed unit and is rethrown rather than retrying partly executed callbacks or
plugin scripts. No rollback, unload or hot reload is claimed. The graph is
validated before any trigger registration or callback execution.

### Ordinary startup scanning is a separate phase

Ordinary `packadd` during init executes plugin scripts immediately. With normal
plugin loading enabled, Neovim's later runtime scan can execute an **unguarded**
script again. Many real plugins use their own loaded guards. The runtime does not
suppress Neovim's global plugin phase or claim that it can make arbitrary plugin
scripts idempotent. The bundle fixture checks both guarded scripts and this
unguarded native behavior explicitly. Load callbacks themselves are not repeated.

The native startup `after/plugin` phase still runs. After-load configuration
executes before that later phase. Deferred loading after startup does not source
`after/plugin`; users may opt into specific work through their own configuration.
`after/ftplugin` belongs to the separate FileType path.

## Trigger handoff

String triggers accept either one string or a list; omission and empty lists
mean no trigger of that kind. These are prototype representations, not final
schema choices.

- `onEvents`: native Neovim event names. Matching pending units are loaded together,
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
  Operator-pending lazy keys (`mode = "o"`) are rejected before registration:
  replay cannot safely preserve every pending operation. Load the target at
  startup and let it define its own operator-pending mappings instead.
  Select and terminal mode coverage remains open.
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
can be reported after startup callbacks have run. Further key-mode and event
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
