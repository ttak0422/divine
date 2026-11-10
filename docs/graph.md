# Offline dependency graph

The provisional `lib.mkGraph { pkgs; configuration; }` API builds a single HTML
file with an interactive graph and inline documentation. It uses the compiler's
validated configuration, so unknown fields and conflicting repeated definitions
fail rather than producing a partial graph. This is a separate export: it does
not change the Neovim runtime or execute inline check functions.

## Export from a flake

For example, add a graph package to your configuration flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    divine.url = "github:ttak0422/divine";
  };

  outputs = { nixpkgs, divine, ... }:
    let
      system = "aarch64-darwin"; # Use your target system.
      pkgs = nixpkgs.legacyPackages.${system};
      configuration = {
        plugins = [
          {
            plugin = pkgs.vimPlugins.telescope-nvim;
            lazy = true;
            onCommands = "Telescope";
            doc = "Search files and buffers. Requires plenary.";
            dependPlugins = [
              {
                plugin = pkgs.vimPlugins.plenary-nvim;
                doc = "Lua helpers used by Telescope.";
              }
            ];
            config = # lua
              ''
                require("telescope").setup({})
              '';
          }
        ];
      };
    in {
      packages.${system}.graph = divine.lib.mkGraph {
        inherit pkgs configuration;
      };
    };
}
```

Use a divine revision containing this provisional API. You can reuse the same
`configuration` value passed to `mkBundle` and `mkDocs`.

```sh
nix build .#graph
open result # macOS
```

On other systems, open the `result` file in a browser. The file includes its SVG,
styles, script and data; it works offline without a web server, CDN or runtime
Graphviz installation. Graphviz is only a Nix build dependency. Building can
still need network access for Nix inputs and build dependencies.

## Read the graph

- Package nodes identify physical plugin output paths. Two packages with the
  same display name remain separate nodes when their output paths differ.
- Solid arrows point from a configuration to its prerequisite. These are
  explicit `dependPlugins` edges, not Nix derivation build dependencies or
  implicit package `dependencies` metadata.
- Package-group configuration nodes represent individual `packages = [ ... ];`
  occurrences. Dashed numbered links show ordered membership, not dependency
  edges. Overlapping groups keep independent documentation and configuration.
- Cycle boundaries show strongly connected components (SCCs), including
  self-dependencies. Each SCC is one load unit; its ownership is separate from
  membership in a package group.
- Roots are entries in the composed configuration. Declaration locations such
  as `plugins[0]` are input positions, not original file names or line numbers.
- A package's own unit can be deferred while the physical package is needed at
  startup by a group. Own-unit startup and physical startup are shown separately;
  membership does not create a new singleton startup demand.

Hover over a node to read its `doc`. Use selection to keep its details visible.
Documentation is displayed as plain text, including any Markdown syntax. HTML
inside labels or docs is not rendered as active content. Missing and empty
inline documentation are valid. Repeated singleton documentation uses existing
settings equality: equal strings merge and conflicting strings fail.

This is a configuration loading graph, not a Nix build graph or a recording of
runtime load events. Lua callback source, check functions and arbitrary package
metadata are excluded. The HTML does include inline docs, output-path identities
and declaration locations: review it for private information before sharing it.

Public API names and group semantics remain provisional. This viewer does not
change the review status of the [resolution policies](resolution.md) or
[architecture decisions](adr/README.md).
