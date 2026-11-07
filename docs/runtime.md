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
Only explicitly declared configuration dependencies are placed; package passthru
metadata is not interpreted as a second dependency graph.

The bundle can be used with `nvim -u /path/to/bundle/init.lua`. Its init entry adds
the bundle to runtimepath and packpath, prepends all recursively collected
`extraPackages` binaries to PATH, registers non-key triggers, executes common startup
configuration, loads startup units, then installs remaining key triggers and
handles already-open filetypes. This lets startup configuration set mapleader
before lazy keys are expanded, while require/command triggers already work.
`runtimePaths` accepts paths or package outputs for additional runtime trees;
existing `after` subdirectories are added separately. It does not source an
entire `after` directory.

Compilation currently requires an explicit `lazy` declaration for every resolved
node. The resolver still accepts and reports omitted timing, but compiling it
fails with a specific unresolved-timing diagnostic instead of inventing a default.
A package shorthand can reference a detailed declaration elsewhere. An explicit
`lazy = true` with no trigger remains available through the returned controller's
manual `load(node_id)` operation. This does not establish the eventual policy for
omitted or triggerless timing.

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

- `onEvents`: native Neovim event names. Only matching handlers introduced by the
  load are replayed; old handlers are not rerun as a whole augroup.
- `onCommands`: full user-command names. The stub loads before invocation and
  forwards arguments, bang, range and modifiers. Completion also loads the target
  and delegates to the newly installed command.
- `onFiletypes`: exact filetype names. Matching current and subsequently opened
  buffers can load the unit. Added ftplugin and after/ftplugin paths are handled
  separately from after/plugin.
- `onKeys`: a key string (normal mode), `{ lhs = "..."; mode = "n"; }`, or a list
  of either. The original operation is fed back after loading; normal-mode count
  and register handling are tested, along with insert, visual and operator-pending
  operations. Select and terminal mode coverage remains open.
- `onModules`: exact Lua module names or dotted namespace prefixes. `foo` matches
  `foo` and `foo.bar`, not `foobar`. The existing Lua searcher chain resumes after
  preparation. Matching plugin names is never substituted for module names.

Duplicate command/key ownership and existing command/key conflicts fail rather
than replacing unrelated user definitions. Events may demand several units.
Key conflicts are checked as a batch after startup configuration, before any key
stubs are installed. This avoids binding a stale mapleader, but means a conflict
can be reported after startup callbacks have run. Further key-mode and event
semantics coverage is tracked in [TODO.md](../TODO.md).

The event replay prototype has limitations: Ex/Vimscript autocmds do not expose
API IDs, so their `++once` removal and script-local command context cannot yet be
faithfully reproduced. API callback autocmds have dedicated identity and once
coverage. These limitations prevent claiming universal first-event equivalence.

## Verification scope

Named nix-unit cases cover compilation as well as graph resolution. The
existing headless runtime check now runs isolated primitives, real opt/SCC
fixtures and native trigger fixtures. The bundle build check starts a fresh
Neovim with generated init, validates opt layout, startup/configuration phases,
command and module handoff, native after/plugin behavior and an external tool.
These tests use small synthetic plugin packages, not a third-party plugin suite.
The selected nix-unit method is recorded separately in
[ADR 0006](adr/0006-use-nix-unit.md). Adopting the test method does not accept the
proposed runtime behavior asserted by its fixtures.
