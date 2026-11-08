# Repeated singleton definitions: remaining review

Status: proposed. This document prepares the remaining
[REPEATED-DEFINITIONS task](../../TODO.md) for review; it does not accept
[ADR 0002](../adr/0002-repeated-definitions.md) or change resolver behavior.

Package output-path identity is already accepted in
[ADR 0001](../adr/0001-output-path-identity.md). Equivalent trigger-form
comparison is the separately approved change in
[PR #14](https://github.com/ttak0422/divine/pull/14), which is not a prerequisite
for the examples or characterization tests here. That approval does not settle
complementary-field composition, edge/tool unions or provenance.

## Recommendation for review

Retain the current composition of complementary top-level settings and the
output-path union of dependencies/tools. Preserve every occurrence location for
diagnostics and retain the first package value for each identity. Keep distinct
settings explicit in Nix, with no precedence or recursive merge added by divine.
This is a recommendation to the owner, not an accepted contract.

### Complementary fields

Assuming `pkgs` is the package set, these occurrences currently supply one
plugin's two different lifecycle fields:

```nix
{
  plugins = [
    {
      plugin = pkgs.vimPlugins.mini-pairs;
      preConfig = # lua
        ''
          vim.g.minipairs_disable = false
        '';
    }
    {
      plugin = pkgs.vimPlugins.mini-pairs;
      config = # lua
        ''
          require("mini.pairs").setup({})
        '';
    }
  ];
}
```

Reversing these declarations retains the same settings. If both supply different
`config` values, they conflict. A user can instead construct one final value in
Nix, including deliberate Lua concatenation, before giving it to divine. Divine
must not guess the intended order of two different configuration bodies.

Options being proposed for review:

- Keep complementary fields, as above. This supports separate modules supplying
  different concerns, but all occurrences of an identity can affect its final
  settings. A dependency reference is not a private copy of that configuration.
- Require one detailed owner per singleton, allowing only package shorthand at
  other locations. Ownership is more explicit, but existing complementary inputs
  would become errors. The owner must also decide how to identify that owner and
  whether identical detailed repetitions are allowed.

Recommended: keep complementary fields. Nested attribute sets are compared as
whole values, not recursively merged. The raw resolver accepts arbitrary
settings for inspection, but that does not make them valid compiler input:
[the compiler schema](../../lib/options.nix) only accepts its declared fields.

### Dependency and tool unions

Assuming `a`, `b` and `c` are plugin derivations:

```nix
{
  plugins = [
    { plugin = a; dependPlugins = [ b ]; }
    { plugin = a; dependPlugins = [ c b ]; }
  ];
}
```

The current graph gives `a` dependencies on both `b` and `c`, deduplicated and
sorted by output path. Both are prerequisites; list order does not prescribe a
load sequence between them. Explicit dependency edges and the SCC rules govern
loading. This is separate from the ordered `packages` occurrence proposal.

The same output-path union applies to `extraPackages` supplied globally and at
any dependency depth. It preserves package values and does not inspect a plugin
package's implicit dependency metadata.

Options being proposed for review:

- Retain the union. Each occurrence can declare its requirements, but the final
  closure can contain requirements not visible at a single declaration site.
- Require repeated dependency/tool sets to agree, or give one detailed owner the
  complete sets. This exposes accidental differences earlier, but makes
  composition across dependency locations more restrictive.

Recommended: retain unions. The order of distinct string triggers is a separate
comparison policy; dependency union is not permission to union trigger lists.

### Provenance and first package values

The current resolver retains paths such as `plugins[0].dependPlugins[0]` for
all occurrences and uses the first declaration location of a field in conflicts.
These are paths in the composed input, not source-file names or line numbers.
Do not treat them as stable public configuration IDs.

When several package values have the same output path, the first value at that
collection boundary represents the identity, including its metadata and Nix
build context. Global tools are considered before collected per-node tools in
the final tool collection; a node's own tools can therefore retain a different
representative from the final global collection. This does not merge metadata.

Options being proposed for review:

- Retain all occurrence paths and first-value representation, as implemented.
  This avoids dropping diagnostic context without inventing metadata merging.
- Add source-file locations or explicit owners before stabilizing provenance.
  That needs a new input/source model; current input paths cannot provide it.

Recommended: retain current provenance as diagnostics, not a promise of stable
IDs or source locations. A later source-location feature can add information
without claiming that the current graph already has it.

## Verification and owner decision

[tests/resolver.nix](../../tests/resolver.nix) already covers repeated fields,
string build contexts, nested conflicts, tools, cycles and deterministic order.
This draft adds named characterization cases for:

- complementary settings in either declaration order;
- exact root and recursive occurrence locations;
- first package/tool representatives and retained package build context;
- dependency/tool unions in either declaration order;
- rejection of a recursive settings merge;
- a conflict message containing the package, field and both locations.

These tests document existing behavior; they do not accept it. Run the full
suite and flake checks as described in [Development](../../README.md#development).

The owner can accept the three recommended policies independently, or choose
an alternative and request its implementation. Until then ADR 0002 and its TODO
remain proposed/open. The ordered-group identity and manual-reference questions
remain in the [API review](api-and-triggers.md).
