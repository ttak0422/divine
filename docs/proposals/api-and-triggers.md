# Public API and trigger policy proposal

Status: proposed. This review document addresses **API** and
**TRIGGER-POLICY** in [TODO.md](../../TODO.md); it changes no runtime behavior,
marks no decision accepted, and does not make the current exports stable.
The source baseline is `93c9499`.

## Constraints and recommendation

Keep the current names and data schema as the candidate public interface rather
than introducing a second representation. This is the smallest compatible
proposal: existing configurations need no migration, and validation and fixtures
already exercise these forms. Compatibility is a reason to propose this choice,
not evidence that the owner has accepted it.

The alternatives for review are to retain this candidate or defer final naming
and schema until a concrete replacement is proposed. No alternative spelling,
public Nix module interface or migration design has been evaluated here. Do not
remove existing fields merely to narrow the proposal.

Preserve the [design requirements](../design.md): identical recursive definition
expressiveness at roots and dependencies; opt placement even for startup loads;
explicit plugin dependencies; Lua text/files; all five trigger categories; and
omitted, single and multiple conditions. Omitted or null `lazy` is unspecified
until merging, then defaults to false. Triggers never imply `lazy = true`.
[ADR 0010](../adr/0010-triggerless-deferred-loading.md) already accepts triggerless
deferral on prerequisite or manual demand; that behavior is not reopened here.

## Candidate public surface

Propose `divine.lib.mkBundle`, `mkDocs` and `mkChecks` as the consumer builders,
with their existing argument/result contracts in [the type reference](../nix-types.md).
Keep the currently exported `inspectDefinitions`, `resolve` and `compile`
available as provisional inspection/compiler interfaces. Do not promise stable
resolved-graph fields, generated Lua plans, SCC IDs or controller entry points as
a side effect of adopting configuration names.

The proposed configuration grammar is the existing compiler grammar:

| Scope | Fields and shape |
| --- | --- |
| Root | Required `plugins` list; optional `extraPackages` list, `startupConfig` Lua text/path and `runtimePaths` list of Nix paths or derivations. |
| Definition | Package shorthand, or a record with exactly one of `plugin` (derivation) and `packages` (nonempty derivation list). |
| Recursive inputs | `dependPlugins` is a list of the same shorthand or detailed definitions at every depth; `extraPackages` is a list of external-tool derivations. |
| Timing and Lua | `lazy` is boolean or null; `preConfig`, `config` and `load` are Lua text or file paths; `loadAfter` is boolean. |
| Trigger fields | `onEvents`, `onCommands`, `onFiletypes`, `onKeys`, `onModules`, as specified below. |
| Documentation and checks | `doc` is Markdown text; mutually exclusive `test` and `tests` hold a check function or named check functions. Package groups require explicit `tests.<name>`. |

Unknown compiler root, definition and key fields remain errors. Input is data,
not a module: using `mkOption`/`evalModules` internally does not authorize
`mkDefault`, `mkMerge` or other module properties in configurations. Raw graph
inspection accepts extension metadata, but that is not a compiler extension API.
The exact current validation is in [lib/options.nix](../../lib/options.nix).

This example uses only current fields and demonstrates shorthand and detailed
dependencies. The caller supplies the divine flake and the Nixpkgs package set:

```nix
{ divine, pkgs }:
divine.lib.mkBundle {
  inherit pkgs;
  configuration = {
    startupConfig = # lua
      ''
        vim.g.mapleader = " "
      '';
    plugins = [
      pkgs.vimPlugins.vim-repeat
      {
        plugin = pkgs.vimPlugins.telescope-nvim;
        lazy = true;
        onCommands = "Telescope";
        dependPlugins = [
          {
            plugin = pkgs.vimPlugins.plenary-nvim;
            lazy = true;
          }
          pkgs.vimPlugins.nvim-web-devicons
        ];
        extraPackages = [ pkgs.ripgrep pkgs.fd ];
        config = # lua
          ''
            require("telescope").setup({})
          '';
      }
    ];
  };
}
```

The shorthand dependency loads at startup by default; the explicitly deferred
prerequisite can wait for Telescope's demand. A detailed dependency can itself
contain `dependPlugins` with the identical grammar. Package derivation metadata
is never an implicit dependency declaration.

### Package groups and manual references remain separate decisions

Retain the implemented `packages` form while reviewing
[ADR 0009](../adr/0009-ordered-package-units.md) separately. For example, this is
current valid configuration data, not acceptance of group semantics:

```nix
{ pkgs }:
{
  plugins = [
    {
      packages = [
        pkgs.vimPlugins.nvim-cmp
        pkgs.vimPlugins.cmp-buffer
      ];
      loadAfter = true;
      config = # lua
        ''
          require("cmp").setup({ sources = { { name = "buffer" } } })
        '';
    }
  ];
}
```

Each group occurrence currently owns independent hooks and timing; copying the
same full definition into two dependencies configures it twice. Ordered members
cannot undo an earlier physical load through another configuration. Those
identity, overlap and first-load policies need ADR 0009 review before the whole
group contract can be called stable.

There is **no stable public manual group-reference API**. Internal
`load(package_path)` targets singleton configuration, not every group containing
that output. Origin-derived group IDs and SCC IDs must not appear as durable
user references. Do not add a guessed `name`, `id`, reference constructor or
public `loadGroup` example: the current schema does not implement them.
[ADR 0003](../adr/0003-prototype-scc-extraction.md) concerns the proposed extraction
algorithm, not public identity; choosing names here does not accept that
algorithm or promise an order among callbacks inside a cycle.

## Candidate trigger grammar

Recommend retaining these current forms for public review:

- `onEvents`, `onCommands`, `onFiletypes`, `onModules`: a nonempty string or a
  list of nonempty strings. Omission and `[]` mean no trigger in that category.
- `onKeys`: a nonempty string, `{ lhs = "<leader>ff"; mode = "n"; }`, or a list mixing
  strings and records. Omitted mode means `"n"`; allowed single modes are
  `"n"`, `"i"`, `"x"`, `"s"`, `"o"`, `"t"`. Use separate records for multiple
  modes. Empty lists are valid; null, empty strings and extra record fields are
  not. Mode lists, patterns and trigger option records are not implemented.
- Multiple conditions, including different trigger categories, are alternatives
  that can demand the same unit, not an AND expression. A successful load clears
  its remaining stubs. A prerequisite may load the unit before its own trigger.

For example, each list entry below is a separate alternative configuration for
the same plugin. Select one entry; do not combine these as repeated definitions:

```nix
{ pkgs }:
map (triggers: {
  plugin = pkgs.vimPlugins.telescope-nvim;
  lazy = true;
  dependPlugins = [ pkgs.vimPlugins.plenary-nvim ];
} // triggers) [
  { } # No own trigger; prerequisite or manual demand only.
  { onCommands = "Telescope"; } # One condition.
  { onModules = [ "telescope.builtin" "telescope.actions" ]; } # Alternatives.
]
```

### Matching and first-operation handoff

Recommend the current bounded contract in [runtime.md](../runtime.md#trigger-handoff),
not universal equivalence to startup loading:

| Category | Current matching and handoff to review |
| --- | --- |
| Events | Canonical native event names, accepting catalog aliases/case. Unknown names fail compilation; running Neovim must support the canonical names. Load pending targets, then replay through eligible new named augroups. Pre-existing event groups and ungrouped handlers are excluded, even if an old group's pattern did not match. |
| Commands | Full user-command names matching `[A-Z][A-Za-z0-9]*`. Load and reparse original arguments with bang, range and modifiers. Completion also loads and delegates. A missing command after loading is an error. |
| Filetypes | Exact filetype strings, including already-open loaded buffers and later matching buffers. Native FileType replay runs globally, including existing/ungrouped handlers and native ftplugin/after-ftplugin loading. |
| Keys | Load then hand the operation back to Neovim. Normal count/register, insert, visual, select and terminal handoff have focused fixtures. Operator-pending load preserves the pending operation but runs under textlock; buffer edits, cursor movement or window switching during load are unsupported. |
| Modules | Exact module names or dotted namespace prefixes: `foo` matches `foo` and `foo.bar`, not `foobar`. Load matching pending targets and continue the existing Lua searcher chain with recursion protection. Plugin names do not substitute for module names. |

Event replay preserves the originating buffer, match and data through native
APIs, but cannot recreate the original read-time state. BufReadPost supplements
BufReadPre; FileType supplements BufReadPre and BufReadPost. Supplements apply
their own group exclusions. FileType deliberately repeats existing handlers;
handlers still pending in the outer dispatch may run again. No original global
registration order across groups or arbitrary first-event equivalence is promised.

Command/key ownership conflicts fail instead of replacing existing definitions.
Leader keys expand after startup configuration; key conflicts are checked as a
batch then, potentially after startup callbacks have run. Event/current-filetype
batches stop on the first failure without replaying the batch; unattempted
independent targets remain reachable. Failed-unit retention, SCC sequencing and
operator failure cleanup are observed implementation behavior, not acceptance of
all failure/phase policies by this document.

### Boundary with normalization PR #14

[PR #14](https://github.com/ttak0422/divine/pull/14), reviewed here at
[`4eca558`](https://github.com/ttak0422/divine/commit/4eca5588b883cba6a21824b3d8dae8853c957458),
separately records accepted normalization of equivalent scalar/list, event and
key forms before comparing repeated singleton fields. It is not part of this
baseline and must not be reimplemented in this proposal. Its normalization does
not adopt public field names, matching/handoff policy or group identity.

On this baseline, compiling one scalar/list trigger works, but combining those
raw forms on repeated singleton definitions can still conflict. Do not use the
proposed grammar to claim they compose already. After PR #14, genuinely different
values and distinct-element ordering still conflict rather than being unioned;
its recorded decision owns those details. This documentation proposal can be
reviewed independently; an implementation relying on that comparison behavior
must include PR #14 first.

## Explicit review decisions still required

1. Adopt the existing field names and three consumer builders, or keep them
   provisional pending a concrete replacement? Do not stabilize graph/plan or
   controller internals implicitly.
2. Adopt the omitted/scalar/list grammar, supported single key modes and OR
   matching described here? Triggerless deferral is already accepted separately.
3. Adopt the exact current event exclusions/supplements, FileType repetition,
   command/completion and module namespace handoff, plus the textlock boundary?
   If not, specify the changed guarantee and fixtures before changing behavior.
4. Accept, revise or continue deferring ADR 0009's group contract? What stable
   manual group identity/reference, if any, should a future API provide? No
   current implementation or syntax answers that question.

A review must record its selected scope explicitly. Merge of this proposal alone
must not check off API/TRIGGER-POLICY or change any ADR status.

## Validation evidence and remaining work

These are existing source fixtures inspected for this proposal, not checks run
by this documentation change:

- [tests/options.nix](../../tests/options.nix): nullable timing, recursive schema,
  unknown fields, invalid/null triggers and rejected module properties.
- [tests/compiler.nix](../../tests/compiler.nix): scalar commands, keys, event
  aliases/case, unknown events, triggerless plans and triggers without deferral.
- [tests/packages.nix](../../tests/packages.nix) and
  [tests/runtime-plan.lua](../../tests/runtime-plan.lua): recursive groups,
  independent configuration, overlap, manual singleton demand and triggerless
  prerequisites. They test a proposed group contract, not stable references.
- [tests/triggers.lua](../../tests/triggers.lua), with the explicit
  [case inventory](../../tests/cases.lua): matching, first/repeated operations,
  event exclusions and context, ownership conflicts and failed batches.
- [tests/events.nix](../../tests/events.nix) and
  [tests/events.lua](../../tests/events.lua): compiled event catalog checks.
  The catalog's upstream provenance is in [lib/events.nix](../../lib/events.nix).
- [tests/real-plugin-events.nix](../../tests/real-plugin-events.nix) and
  [runtime verification limits](../runtime.md#verification-scope): vim-lastplace
  first-read restoration and nvim-cmp/cmp-buffer interaction. These focused
  checks do not establish compatibility with arbitrary plugins or events.

Documentation validation should check relative links, fenced examples and
whitespace. The snippets above were checked against the current schema by source
inspection, not evaluated with Nix. No Nix executable is available in this editing
environment, so `make test`, `nix flake check --print-build-logs` and the Nix-backed
style checks were not run. Before a behavior-changing follow-up, run those
repository checks in the supported development environment, add fixtures for
any newly selected guarantees and report executed tests separately from
evaluation. Keep normalization coverage and acceptance in PR #14.
