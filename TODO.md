# Implementation tasks

These items are not implicitly decided by the prototype's names or behavior.
The design snapshot remains the behavior contract.
[ADRs](docs/adr/README.md) track decision status separately: a checked implementation
item does not mean its design has been accepted.

- [ ] **API**: choose public names/schema; root and dependency definitions must keep the same recursive expressiveness.
- [ ] **DEFAULTS**: lazy defaults to true for shorthand and omitted timing; remaining triggerless policy and unspecified/single/multiple trigger representation need review.
- [ ] **IDENTITY**: review/adopt or revise the prototype's output-path identity, field equality/conflict errors, edge/tool unions and retained provenance; see docs/resolution.md.
- [ ] **CYCLES**: review/adopt or revise finite back-references through package identity; directly cyclic Nix values remain distinct from finite cyclic graphs.
- [x] **INPUT-SCHEMA**: validate compiler inputs with mkOption types/descriptions and nullable timing before the existing resolver; public module API and generated documentation remain separate.
- [x] **PLAN**: prototype finite graph normalization, SCC extraction and dependency-first load units, including cycles and self-dependencies.
- [x] **EXTRACTION**: extract global, root and recursively nested extraPackages, preserving derivations and deduplicating by output path.
- [x] **UNIT-RUNTIME**: prepare every SCC member before phased configuration; sequencing remains proposed in ADR 0005.
- [ ] **STARTUP-DEMAND**: review the prototype's dependency-closure startup demand, which retains original timing declarations and opt placement.
- [x] **PACKAGING**: build opt-only trees for explicit configuration dependencies and check no start promotion.
- [x] **GENERATION**: emit Lua callbacks from text/files and add recursive external tools and runtimePaths.
- [x] **STARTUP**: generated init registers the runtime and loads explicit startup demand through the shared SCC path.
- [ ] **EVENT**: native group replay covers API/Vimscript once and script context; broaden real-plugin event compatibility beyond isolated fixtures.
- [x] **COMMAND**: native command stubs and invocation/completion handoff; see runtime fixtures for verified argument forms.
- [x] **FILETYPE**: match current/new buffers and handle new ftplugin/after-ftplugin separately.
- [ ] **KEY**: key operation replay is implemented with normal-mode count/register and insert/visual coverage; operator-pending keys retain native state with a textlock-bound load; add select/terminal fixtures.
- [x] **MODULE**: native require handoff with proposed exact/dotted namespace matching and recursion protection.
- [ ] **DOCS**: generate configuration documentation from resolved input and record source provenance.
- [x] **FAILURES**: proposed unit states, retained errors, reentry and no automatic retry; tested with shared dependencies and native triggers.
- [ ] **AFTER**: native startup/deferred absence and FileType/after-ftplugin fixtures exist; add explicit user opt-in after/plugin sourcing coverage.

- [ ] **NATIVE-STARTUP**: review whether ordinary repeated native scanning of unguarded plugin scripts needs a future explicit alternative; current behavior is documented and tested.
- [x] **TEST-METHOD**: adopt pinned nix-unit with named cases, expected errors, case-discovery and failure-injection guards; legacy default runner replaced.
- [x] **LUA-TEST-METHOD**: use pinned test-only mini.test, named cases with fresh child state, explicit case discovery and nonzero-failure/cleanup guards.
- [x] **NIXPKGS-DEPENDENCIES**: ignore implicit plugin metadata without rewriting derivations; cover two real text-object plugins, a selected shared dependency and nested tools.
- [ ] **REAL-PLUGINS**: broaden third-party coverage beyond the text-object dependency regression and synthetic opt fixtures.

## Fixed boundaries

- A non-delayed target remains in opt; it is explicitly loaded at startup.
- Lua settings run before loading, then default packadd, then after loading.
- Default loading does not source after/plugin after startup. Explicit per-target handling stays with the user.
- An after action does not guarantee completion of native after/plugin. FileType uses a separate runtime search.
- No external loader/wrapper has been selected. Native denops support and general hot swap/unload/reload are outside scope.
