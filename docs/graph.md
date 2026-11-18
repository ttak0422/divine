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
Graphviz installation. Graphviz and the nixpkgs Markdown parser (markdown-it-py)
are build dependencies only. Building can still need network access for Nix inputs
and build dependencies.

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
Documentation renders CommonMark headings, paragraphs, nested lists, emphasis,
blockquotes, inline and fenced code, and links. Parsing happens during the Nix
build; the browser creates only allowed DOM elements and never inserts doc HTML.
Raw HTML stays literal, and images show their alternative text without loading
resources, including embedded images. Only absolute HTTP, HTTPS and mailto links
are active; they open on explicit activation with no opener or referrer. Relative,
protocol-relative and unsafe URL schemes stay inert. Labels remain plain text.
Missing and empty inline documentation are valid. Repeated singleton documentation uses existing
settings equality: equal strings merge and conflicting strings fail.

Use the zoom buttons, Fit or 100% as before. Over the diagram, hold Ctrl while
turning the mouse wheel, or pinch on a trackpad, to zoom around the pointer
(within the scrollable bounds). Ordinary wheel and two-finger scrolling still
pan the diagram; scrolling the inspector or page is unchanged. Pixel, line and
page wheel deltas are normalized. Safari's gesture events are supported alongside
the Ctrl-wheel pinch events used by other browsers. Gestures outside the diagram
retain the browser's normal behavior.

This is a configuration loading graph, not a Nix build graph or a recording of
runtime load events. Lua callback source, check functions and arbitrary package
metadata are excluded. The HTML does include inline docs, output-path identities
and declaration locations: review it for private information before sharing it.

Public API names and group semantics remain provisional. This viewer does not
change the review status of the [resolution policies](resolution.md) or
[architecture decisions](adr/README.md).

## Browser layout check

The Nix checks include generated HTML and dependency-free viewer contract tests.
For an additional real-browser regression check, with Playwright's Python package
and Chromium already installed, run:

```sh
nix build .#graph
python3 tests/graph-browser.py result
```

This uses the exported viewer with a synthetic tall SVG and checks viewport
containment, Fit, ordinary wheel scrolling, pointer-anchored Ctrl-wheel zoom,
synthetic Safari gestures, inspector scrolling, and narrow-screen layout. The
fixture HTML from the graph check also exercises Markdown and hostile docs.
Browser automation does not verify physical trackpad gesture delivery or replace
manual testing on each browser and operating system. It does not add a browser
dependency to the normal development shell or runtime bundle.
