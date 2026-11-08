# Implementation tasks

These items are not implicitly decided by the prototype's names or behavior.
The design snapshot remains the behavior contract.
[ADRs](docs/adr/README.md) track decision status separately: a checked implementation
item does not mean its design has been accepted.

- [ ] **API**: choose public names/schema; root and dependency definitions must keep the same recursive expressiveness.
- [x] **DEFAULTS**: `lazy` defaults to `false` after merging repeated definitions at every dependency depth; omission and `null` leave timing unspecified until then. Triggers do not imply deferral; use explicit `lazy = true`.
- [ ] **TRIGGER-POLICY**: review triggerless deferred loading and omitted/single/multiple trigger representations; the prototype supports prerequisite/manual loading without triggers, but these policies remain provisional.
- [x] **IDENTITY**: use output-path identity for package nodes within one resolved graph (ADR 0001); configuration-unit identity and a possible multi-package API remain separate API decisions.
- [ ] **REPEATED-DEFINITIONS**: review/adopt or revise field equality/conflict errors, edge/tool unions and retained provenance (ADR 0002); accepting package identity does not accept these policies.
- [x] **CYCLES**: use finite package occurrences as back-references, including cycles and self-dependencies (ADR 0001); directly cyclic Nix values remain outside the finite-input contract.
- [x] **INPUT-SCHEMA**: validate compiler inputs with mkOption types/descriptions and nullable timing before the existing resolver; public module API and generated documentation remain separate.
- [x] **PLAN**: prototype finite graph normalization, SCC extraction and dependency-first load units, including cycles and self-dependencies.
- [x] **EXTRACTION**: extract global, root and recursively nested extraPackages, preserving derivations and deduplicating by output path.
- [x] **UNIT-RUNTIME**: prepare every SCC member before phased configuration; sequencing remains proposed in ADR 0005.
- [ ] **STARTUP-DEMAND**: review the prototype's dependency-closure startup demand, which retains original timing declarations and opt placement.
- [x] **PACKAGING**: build opt-only trees for explicit configuration dependencies and check no start promotion.
- [x] **GENERATION**: emit Lua callbacks from text/files and add recursive external tools and runtimePaths.
- [x] **STARTUP**: generated init registers the runtime and loads resolved startup demand, including default startup targets, through the shared SCC path.
- [ ] **EVENT**: native group replay covers API/Vimscript once and script context; broaden real-plugin event compatibility beyond isolated fixtures.
- [x] **COMMAND**: native command stubs and invocation/completion handoff; see runtime fixtures for verified argument forms.
- [x] **FILETYPE**: match current/new buffers and handle new ftplugin/after-ftplugin separately.
- [ ] **KEY**: key operation replay is implemented with normal-mode count/register and insert/visual coverage; operator-pending keys retain native state with a textlock-bound load; add select/terminal fixtures.
- [x] **MODULE**: native require handoff with proposed exact/dotted namespace matching and recursion protection.
- [x] **DOCS**: generate standalone Markdown from inline `doc`, package identities and composed-input declaration locations; source-file line tracking and option documentation remain separate.
- [x] **INLINE-CHECKS**: collect definition-local named Nix test functions into separate derivations, reject duplicate names, and keep test dependencies out of runtime outputs. Public names remain provisional.
- [x] **FAILURES**: proposed unit states, retained errors, reentry and no automatic retry; tested with shared dependencies and native triggers.
- [x] **AFTER**: explicit `loadAfter` supports after/plugin and late after/ftdetect; native startup, first-file FileType, disabled scanning, failures, source deduplication, ftplugin/indent/syntax and real cmp-buffer registration are covered. Review provisional timing in ADR 0008.

- [ ] **NATIVE-STARTUP**: review whether ordinary repeated native scanning of unguarded plugin scripts needs a future explicit alternative; current behavior is documented and tested.
- [x] **TEST-METHOD**: adopt pinned nix-unit with named cases, expected errors, case-discovery and failure-injection guards; legacy default runner replaced.
- [x] **LUA-TEST-METHOD**: use pinned test-only mini.test, named cases with fresh child state, explicit case discovery and nonzero-failure/cleanup guards.
- [x] **NIXPKGS-DEPENDENCIES**: ignore implicit plugin metadata without rewriting derivations; cover two real text-object plugins, a selected shared dependency and nested tools.
- [ ] **REAL-PLUGINS**: broaden third-party coverage beyond the text-object dependency regression and synthetic opt fixtures.

## Fixed boundaries

- A non-delayed target remains in opt; it is explicitly loaded at startup.
- Lua settings run before loading, then default packadd, then after loading.
- Default loading does not source after/plugin after startup. `loadAfter = true` is an explicit per-target opt-in.
- An after action does not guarantee completion of native after/plugin. FileType uses a separate runtime search.
- No external loader/wrapper has been selected. Native denops support and general hot swap/unload/reload are outside scope.
