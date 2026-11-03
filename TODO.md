# Implementation tasks

These items are not implicitly decided by the prototype's names or behavior.
The design snapshot remains the behavior contract.

- [ ] **API**: choose public names/schema; root and dependency definitions must keep the same recursive expressiveness.
- [ ] **DEFAULTS**: decide shorthand/omitted load timing, triggerless definitions, and unspecified/single/multiple trigger representation.
- [ ] **IDENTITY**: review/adopt or revise the prototype's output-path identity, field equality/conflict errors, edge/tool unions and retained provenance; see docs/resolution.md.
- [ ] **CYCLES**: review/adopt or revise finite back-references through package identity; directly cyclic Nix values remain distinct from finite cyclic graphs.
- [x] **PLAN**: prototype finite graph normalization, SCC extraction and dependency-first load units, including cycles and self-dependencies.
- [x] **EXTRACTION**: extract global, root and recursively nested extraPackages, preserving derivations and deduplicating by output path.
- [ ] **UNIT-RUNTIME**: prepare every SCC member's runtime before related configuration; decide execution details within a unit.
- [ ] **STARTUP-DEMAND**: review the prototype's dependency-closure startup demand, which retains original timing declarations and opt placement.
- [ ] **PACKAGING**: place managed plugins and dependencies in opt; inspect the generated layout for dependency promotion.
- [ ] **GENERATION**: emit Lua/actions from declarations and adjacent Lua files; add external executables/runtime files without plugin-specific Nix setup conversion.
- [ ] **STARTUP**: initialize the runtime during init and explicitly load non-delayed opt entries through the same before/load/after path.
- [ ] **EVENT**: register event triggers and preserve the first event's behavior.
- [ ] **COMMAND**: register command triggers and hand off arguments, bang/range/modifiers and completion.
- [ ] **FILETYPE**: handle matching filetypes and the first/current buffer.
- [ ] **KEY**: load on a key operation and hand off the original operation; a command mapping alone is not this trigger.
- [ ] **MODULE**: load before module resolution; decide matching scope, recursion and initial require handoff.
- [ ] **DOCS**: generate configuration documentation from resolved input and record source provenance.
- [ ] **FAILURES**: specify load state, errors and reentry for shared dependencies; test startup and every first trigger.
- [ ] **AFTER**: integration fixtures for native after/plugin during startup, explicit opt-in sourcing after startup, and the separate FileType/after-ftplugin path.
- [ ] **COMPATIBILITY**: test Neovim 0.12.4 separately from the development shell's Neovim.

## Fixed boundaries

- A non-delayed target remains in opt; it is explicitly loaded at startup.
- Lua settings run before loading, then default packadd, then after loading.
- Default loading does not source after/plugin after startup. Explicit per-target handling stays with the user.
- An after action does not guarantee completion of native after/plugin. FileType uses a separate runtime search.
- No external loader/wrapper has been selected. Native denops support and general hot swap/unload/reload are outside scope.
