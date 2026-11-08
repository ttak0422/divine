# Implementation tasks

These items are not implicitly decided by the prototype's names or behavior.
The design snapshot remains the behavior contract.
[ADRs](docs/adr/README.md) track decision status separately: a checked implementation
item does not mean its design has been accepted.

- [ ] **API**: choose public names/schema; root and dependency definitions must keep the same recursive expressiveness.
- [x] **DEFAULTS**: `lazy` defaults to `false` after merging repeated definitions at every dependency depth; omission and `null` leave timing unspecified until then. Triggers do not imply deferral; use explicit `lazy = true`.
- [x] **TRIGGERLESS**: allow explicit deferred targets without triggers; load only on prerequisite or manual demand, without inferring deferral from trigger declarations (ADR 0010). This does not establish a stable manual group-reference API.
- [ ] **TRIGGER-POLICY**: choose public omitted/single/multiple trigger representations, matching and handoff details; triggerless loading semantics are accepted separately in ADR 0010.
- [x] **IDENTITY**: use output-path identity for package nodes within one resolved graph (ADR 0001); configuration-unit identity and a possible multi-package API remain separate API decisions.
- [x] **TRIGGER-NORMALIZATION**: compare equivalent trigger forms canonically in Nix, preserving order and string context and rejecting other differences (ADR 0011).
- [ ] **REPEATED-DEFINITIONS**: review the remaining complementary-field composition, edge/tool unions and provenance policies (ADR 0002); accepted trigger normalization and strict comparison do not adopt these policies.
- [x] **CYCLES**: use finite package occurrences as back-references, including cycles and self-dependencies (ADR 0001); directly cyclic Nix values remain outside the finite-input contract.
- [x] **INPUT-SCHEMA**: validate compiler inputs with mkOption types/descriptions and nullable timing before the existing resolver; public module API and generated documentation remain separate.
- [x] **PLAN**: prototype finite graph normalization, SCC extraction and dependency-first load units, including cycles and self-dependencies.
- [x] **EXTRACTION**: extract global, root and recursively nested extraPackages, preserving derivations and deduplicating by output path.
- [x] **UNIT-RUNTIME**: prepare every SCC member before phased configuration; sequencing remains proposed in ADR 0005.
- [x] **STARTUP-DEMAND**: propagate startup demand through prerequisite units, retaining original timing declarations and opt placement (ADR 0004).
- [x] **PACKAGING**: build opt-only trees for explicit configuration dependencies and check no start promotion.
- [x] **GENERATION**: emit Lua callbacks from text/files and add recursive external tools and runtimePaths.
- [x] **STARTUP**: generated init registers the runtime and loads resolved startup demand, including default startup targets, through the shared SCC path.
- [x] **EVENT**: native group replay has API/Vimscript once/context fixtures plus real vim-lastplace first-read cursor restoration and nvim-cmp first-InsertEnter mapping/completion checks; existing-group exclusions and first-event limitations remain documented.
- [x] **COMMAND**: native command stubs and invocation/completion handoff; see runtime fixtures for verified argument forms.
- [x] **FILETYPE**: match current/new buffers and handle new ftplugin/after-ftplugin separately.
- [x] **KEY**: key operation replay covers normal-mode count/register, insert/visual operations, native-parity select character/line/block selections and terminal input on first/repeated keys; operator-pending keys retain native state with a textlock-bound load.
- [x] **MODULE**: native require handoff with proposed exact/dotted namespace matching and recursion protection.
- [x] **DOCS**: generate standalone Markdown from inline `doc`, package identities and composed-input declaration locations; source-file line tracking and option documentation remain separate.
- [x] **INLINE-CHECKS**: collect definition-local named Nix test functions into separate derivations, reject duplicate names, and keep test dependencies out of runtime outputs. Public names remain provisional.
- [x] **FAILURES**: proposed unit states, retained errors, reentry and no automatic retry; tested with shared dependencies and native triggers.
- [x] **AFTER**: explicit `loadAfter` supports after/plugin and late after/ftdetect; uniform startup/deferred before-config timing, first-file FileType, disabled scanning, synchronous failures, source deduplication, preserved runtime assets and real cmp-buffer registration have checks. Review the generated opt-view and timing proposal in ADR 0008; broader path-sensitive plugin compatibility remains open.

- [ ] **NATIVE-STARTUP**: review whether ordinary repeated native scanning of unguarded plugin scripts needs a future explicit alternative; current behavior is documented and tested.
- [x] **TEST-METHOD**: adopt pinned nix-unit with named cases, expected errors, case-discovery and failure-injection guards; legacy default runner replaced.
- [x] **LUA-TEST-METHOD**: use pinned test-only mini.test, named cases with fresh child state, explicit case discovery and nonzero-failure/cleanup guards.
- [x] **NIXPKGS-DEPENDENCIES**: ignore implicit plugin metadata without rewriting derivations; cover two real text-object plugins, a selected shared dependency and nested tools.
- [x] **REAL-PLUGINS**: focused checks cover text-object dependencies/operations, Telescope/project.nvim/mini.pairs behavior, cmp-buffer registration, and startup/deferred vim-lastplace and nvim-cmp event-driven behavior; see docs/runtime.md for the exact scope and limitations.

## Fixed boundaries

- A non-delayed target remains in opt; it is explicitly loaded at startup.
- Lua settings run before loading, then default packadd, then after loading.
- Default loading does not source after/plugin after startup. `loadAfter = true` is an explicit per-target opt-in.
- With `loadAfter = true`, original after/plugin files run synchronously before config and are hidden from the generated native opt view. Default config does not guarantee completion of native after/plugin. FileType uses a separate runtime search.
- No external loader/wrapper has been selected. Native denops support and general hot swap/unload/reload are outside scope.
