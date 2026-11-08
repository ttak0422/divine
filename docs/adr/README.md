# Architecture decision records

Use a lightweight adaptation of the
[MADR minimal template](https://github.com/adr/madr/blob/4.0.0/template/adr-template-minimal.md).
ADRs follow the [project language guidelines](../../CONTRIBUTING.md#language).
Each record keeps the minimal context, options and outcome, plus `status`,
`date`, `discussion`, the reason for the choice, and positive and negative
consequences. The local `discussion` metadata points to the PR or issue where
the decision can be reviewed.

## Writing a record

1. Copy [template.md](template.md) to `NNNN-short-title.md`, using the next unused
   four-digit number. Keep one decision per record; link related decisions.
2. Start with `status: proposed`. Use `date` for the last substantive update to
   the record, not an inferred historical acceptance date.
3. Describe the problem and existing constraints. List only options actually
   recorded or discussed. One option is enough when no alternative is documented;
   say so rather than inventing a comparison or a rejection.
4. State the proposed or chosen option and its reason. If the reason is unknown,
   record that gap for review. Include both positive and negative consequences;
   use "Not yet identified" when appropriate rather than inventing evidence.
5. Link the review discussion and implementation or tests where useful. State
   implementation progress separately from the decision's status. Add the record
   to the index below.

Keep the core sections in the template. Add sections such as open questions or
implementation evidence only when useful; a full MADR checklist is not required.

### Dependency versions

Record the choice and its rationale, not a copy of the current dependency
versions. Refer to [flake.lock](../../flake.lock) for the locked inputs and
[flake.nix](../../flake.nix) for package selection; the selected nixpkgs
definitions determine the concrete package versions. Do not duplicate those
versions or revisions in an ADR. Routine lock updates do not require ADR edits.

Include an exact version only when it is necessary to understand a historical
decision or compatibility constraint. Label it as historical evidence with its
date and source, not as the current dependency requirement. Preserve stable
source citations, such as the upstream template link above, as provenance.

## Status and review

- `proposed`: under review, including choices already used by the prototype.
- `accepted`: explicitly adopted through project review. Link the acceptance in
  `discussion`; passing tests, an implementation or a merged PR alone is not
  evidence that a provisional design was adopted.
- `rejected`: reviewed and not adopted; retain the record and reason.
- `deprecated`: no longer applicable; retain the record and reason.
- `superseded`: replaced by another ADR; link the replacement in the outcome and
  link back from the new record.

Do not rewrite an accepted decision to hide its history. A material change gets
a new record; clarifications can update the existing record and its date.

[design.md](../design.md) remains the behavior contract, including its unresolved
questions. [resolution.md](../resolution.md) describes the current prototype.
[TODO.md](../../TODO.md) tracks missing implementation and pending decisions.
ADRs record the reasoning and review state; they do not silently replace those
requirements or turn prototype behavior into a stable API. The design snapshot
also follows the project-wide English policy; translation does not change its
requirements or the status of unresolved decisions.

## Records

These records distinguish accepted decisions from prototype choices still under
review. Dates describe each record's substantive update; a proposed record's date
is not a historical approval date. Package-node identity and finite references
are accepted in ADR 0001. Public names, configuration-unit identity, a possible
multi-package interface and within-unit execution are not settled by that record.
Startup prerequisite demand is accepted in ADR 0004; triggerless deferred loading
is accepted in ADR 0010. Neither accepts public names, trigger representations
or stable manual group references. The `lazy = false` default is specified
separately in the design requirements. Comparison after equivalent trigger
normalization is accepted in ADR 0011; the remaining composition policies in
ADR 0002 stay proposed.

- [0001: Use output-path identity for finite package back-references](0001-output-path-identity.md) (`accepted`).
- [0002: Combine repeated definitions with explicit conflicts](0002-repeated-definitions.md) (`proposed`).
- [0003: Use mutual reachability for prototype SCC extraction](0003-prototype-scc-extraction.md) (`proposed`).
- [0004: Propagate startup demand through prerequisite units](0004-startup-demand.md) (`accepted`).

- [0005: Prepare SCC runtimes before phased configuration](0005-scc-runtime-phases.md) (`proposed`).
- [0006: Use nix-unit for Nix logic tests](0006-use-nix-unit.md) (`accepted`).
- [0007: Use mini.test for Lua behavior tests](0007-use-mini-test.md) (`accepted`).

- [0008: Supplement after directories through explicit opt-in](0008-opt-in-after-loading.md) (`proposed`).

- [0009: Configure ordered packages as independent units](0009-ordered-package-units.md) (`proposed`).

- [0010: Allow deferred targets without triggers](0010-triggerless-deferred-loading.md) (`accepted`).

- [0011: Normalize equivalent trigger forms before comparison](0011-normalize-repeated-trigger-forms.md) (`accepted`).
