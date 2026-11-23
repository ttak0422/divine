{ lib }:
let
  api = import ../lib { inherit lib; };
  package = name: suffix: {
    type = "derivation";
    inherit name;
    outPath = "/nix/store/00000000000000000000000000000000-${suffix}";
  };
  a = package "same-name" "a";
  b = package "same-name" "b";
  c = package "c" "c";
  id = p: toString p;
  project =
    configuration: import ../lib/graph/data.nix { inherit lib; } (api.compile configuration).graph;
  view = plugins: (project { inherit plugins; }).data;
  node = data: key: lib.findFirst (n: n.id == key) (throw "missing graph node") data.nodes;
  group = "packages:plugins[0]";
  pkgs = {
    graphviz = "graphviz-build-only";
    python3.withPackages =
      select:
      assert select { markdown-it-py = "markdown-parser"; } == [ "markdown-parser" ];
      "python-build-only";
    writeText = name: text: "FILE:${name}\n${text}\nEND:${name}";
    runCommand = name: attrs: script: { inherit name attrs script; };
  };
  render = configuration: api.mkGraph { inherit pkgs configuration; };
  jsonInput =
    configuration:
    builtins.head (
      lib.splitString "\nEND:divine-graph.json" (
        builtins.elemAt (lib.splitString "FILE:divine-graph.json\n" (render configuration).script) 1
      )
    );
  renderedData =
    configuration: builtins.fromJSON (builtins.unsafeDiscardStringContext (jsonInput configuration));
  tool = {
    type = "derivation";
    pname = "root/tool";
    name = throw "pname should win over name";
    outPath = throw "runtime tool outPath was evaluated";
  };
  toolA = package "same-tool" "tool-a";
  toolB = package "same-tool" "tool-b";
  toolContextPath = builtins.toFile "divine-graph-tool-context" "fixture";
  contextualTool = tool // {
    pname = builtins.appendContext "context-free-display" (builtins.getContext toolContextPath);
  };
  toolFixture = {
    extraPackages = [
      tool
      tool
      contextualTool
      (builtins.removeAttrs tool [
        "pname"
        "name"
      ])
    ];
    plugins = [
      {
        plugin = a;
        dependPlugins = [ b ];
        extraPackages = [ toolA ];
      }
      {
        plugin = a;
        extraPackages = [
          toolA
          toolB
        ];
      }
      {
        plugin = b;
        dependPlugins = [ a ];
      }
      {
        packages = [ c ];
        dependPlugins = [ a ];
        extraPackages = [ tool ];
      }
    ];
  };
  noToolFixture = {
    plugins = map (definition: builtins.removeAttrs definition [ "extraPackages" ]) toolFixture.plugins;
  };
  repeated = view [
    {
      plugin = a;
      doc = "Shared docs";
    }
    {
      plugin = a;
      doc = "Shared docs";
    }
  ];
  ordered = view [
    {
      packages = [
        b
        a
        b
      ];
      doc = "Group docs";
    }
  ];
  hostile = "</script><script>globalThis.graphInjected=true</script> & \"quoted\" 日本語 @@GRAPH_SVG@@ @@GRAPH_DATA@@";
  malicious = package hostile "malicious";
  unsafeConfiguration.plugins = [
    {
      plugin = malicious;
      doc = hostile;
    }
  ];
  # Inspect only the embedded HTML, not raw DOT passed separately to Graphviz.
  unsafeRendered = builtins.head (
    lib.splitString "END:divine-graph-suffix.html" (
      builtins.elemAt (lib.splitString "FILE:divine-graph-suffix.html\n" (render unsafeConfiguration).script) 1
    )
  );
  callbacks.plugins = [
    {
      plugin = a;
      preConfig = "private_before_callback()";
      config = "private_after_callback()";
      load = "private_load_callback()";
      tests.mustNotRun = _: throw "graph invoked a check body";
    }
  ];
  graphFixture.plugins = [
    {
      plugin = a;
      doc = "Public docs";
      dependPlugins = [ b ];
    }
  ];
  invalidRuntimeEvent.plugins = [
    ((builtins.head graphFixture.plugins) // { onEvents = "NotANeovimEvent"; })
  ];
  invalid = configuration: {
    expr = (render configuration).script;
    expectedError.type = "ThrownError";
  };
in
{
  testOutputPathIdentity = {
    expr =
      map (n: { inherit (n) id label; })
        (view [
          a
          b
          a
        ]).nodes;
    expected = [
      {
        id = id a;
        label = "same-name";
      }
      {
        id = id b;
        label = "same-name";
      }
    ];
  };
  testUniqueSvgIdentity = {
    expr =
      let
        nodes =
          (view [
            a
            b
          ]).nodes;
      in
      builtins.length (lib.unique (map (n: n.svgId) nodes));
    expected = 2;
  };
  testRepeatedDocumentation = {
    expr = {
      count = builtins.length repeated.nodes;
      inherit (node repeated (id a)) doc origins;
    };
    expected = {
      count = 1;
      doc = "Shared docs";
      origins = [
        "plugins[0]"
        "plugins[1]"
      ];
    };
  };
  testConflictingDocumentation = invalid {
    plugins = [
      {
        plugin = a;
        doc = "first";
      }
      {
        plugin = a;
        doc = "second";
      }
    ];
  };
  testNestedDependencies = {
    expr =
      let
        data = view [
          {
            plugin = a;
            dependPlugins = [
              {
                plugin = b;
                dependPlugins = [ c ];
              }
            ];
          }
        ];
      in
      {
        roots = data.roots;
        edges = map (n: n.dependencies) data.nodes;
      };
    expected = {
      roots = [ (id a) ];
      edges = [
        [ (id b) ]
        [ (id c) ]
        [ ]
      ];
    };
  };
  testCycleOwnership = {
    expr =
      let
        data = view [
          {
            plugin = a;
            dependPlugins = [ b ];
          }
          {
            plugin = b;
            dependPlugins = [ a ];
          }
        ];
      in
      {
        cyclic = map (n: n.cyclic) data.nodes;
        owners = lib.unique (map (n: n.unitId) data.nodes);
        count = builtins.length data.units;
      };
    expected = {
      cyclic = [
        true
        true
      ];
      owners = [ (id a) ];
      count = 1;
    };
  };
  testSelfLoop = {
    expr =
      let
        data = view [
          {
            plugin = a;
            dependPlugins = [ a ];
          }
        ];
      in
      {
        inherit (node data (id a)) cyclic dependencies;
      };
    expected = {
      cyclic = true;
      dependencies = [ (id a) ];
    };
  };
  testOrderedMembershipIsNotDependency = {
    expr = { inherit (node ordered group) members dependencies; };
    expected = {
      members = [
        (id b)
        (id a)
      ];
      dependencies = [ ];
    };
  };
  testMembershipDotStyle = {
    expr =
      lib.hasInfix "arrowhead=none, constraint=false, label=\"1\""
        (project {
          plugins = [
            {
              packages = [
                b
                a
              ];
            }
          ];
        }).dot;
    expected = true;
  };
  testOverlappingGroupDocs = {
    expr =
      let
        data = view [
          {
            packages = [
              a
              b
            ];
            doc = "first";
          }
          {
            packages = [
              b
              c
            ];
            doc = "second";
          }
        ];
      in
      map (key: (node data key).doc) [
        group
        "packages:plugins[1]"
        (id b)
      ];
    expected = [
      "first"
      "second"
      null
    ];
  };
  testOwnUnitVersusPhysicalStartup = {
    expr = { inherit (node ordered (id a)) unitStartup physicalStartup; };
    expected = {
      unitStartup = false;
      physicalStartup = true;
    };
  };
  testMissingAndEmptyDocumentation = {
    expr =
      map (n: n.doc)
        (view [
          a
          {
            plugin = b;
            doc = "";
          }
        ]).nodes;
    expected = [
      null
      ""
    ];
  };
  testEmptyGraph = {
    expr = view [ ];
    expected = {
      nodes = [ ];
      roots = [ ];
      units = [ ];
      rootExtraPackageNames = [ ];
    };
  };
  testMaliciousDataRoundTrip = {
    expr =
      let
        data = builtins.fromJSON (builtins.toJSON (project unsafeConfiguration).data);
      in
      {
        inherit (node data (id malicious)) label doc;
      };
    expected = {
      label = hostile;
      doc = hostile;
    };
  };
  # Generated HTML tests verify escaping after the build-time Markdown step.
  testDocDataSeparateFromHtmlTemplate = {
    expr =
      lib.hasInfix "@@GRAPH_DATA@@" unsafeRendered
      && !(lib.hasInfix hostile unsafeRendered)
      && lib.hasInfix "python-build-only/bin/python" (render unsafeConfiguration).script;
    expected = true;
  };
  testChecksAndCallbacksExcluded = {
    expr =
      let
        json = builtins.toJSON (project callbacks).data;
        html = (render callbacks).script;
      in
      builtins.deepSeq html (
        lib.all (value: !(lib.hasInfix value json) && !(lib.hasInfix value html)) [
          "private_before_callback"
          "private_after_callback"
          "private_load_callback"
          "mustNotRun"
        ]
      );
    expected = true;
  };
  testGraphSkipsRuntimePlan = {
    # A well-typed runtime path may be unreadable in a graph-only environment.
    # The graph, DOT and HTML inputs must stay unchanged.
    expr = map (configuration: (render configuration).script == (render graphFixture).script) [
      invalidRuntimeEvent
      (graphFixture // { startupConfig = ./missing-graph-runtime.lua; })
    ];
    expected = [
      true
      true
    ];
  };
  testRuntimeStillValidatesPlan = {
    expr = {
      plan = (builtins.tryEval (api.compile invalidRuntimeEvent).plan).success;
      bundle =
        (builtins.tryEval
          (api.mkBundle {
            inherit pkgs;
            configuration = invalidRuntimeEvent;
          }).script
        ).success;
    };
    expected = {
      plan = false;
      bundle = false;
    };
  };
  testGraphToolLabelsAndTopology = {
    expr =
      let
        rendered = renderedData toolFixture;
        topology = data: {
          inherit (data) units roots;
          nodes = map (item: builtins.removeAttrs item [ "extraPackageNames" ]) data.nodes;
        };
      in
      {
        root = rendered.rootExtraPackageNames;
        singleton = (node rendered (id a)).extraPackageNames;
        group = (node rendered "packages:plugins[3]").extraPackageNames;
        unchangedTopology = topology rendered == topology (renderedData noToolFixture);
        renderedWithoutToolContext =
          !(builtins.hasAttr (builtins.unsafeDiscardStringContext toolContextPath) (
            builtins.getContext (jsonInput toolFixture)
          ));
      };
    expected = {
      root = [
        "root/tool"
        "context-free-display"
        "(unnamed package)"
      ];
      singleton = [ "same-tool" ];
      group = [ "root/tool" ];
      unchangedTopology = true;
      renderedWithoutToolContext = true;
    };
  };
  testRuntimeToolPathValidationAndDedup = {
    expr = {
      plan = (builtins.tryEval (api.compile toolFixture).plan).success;
      bundle =
        (builtins.tryEval
          (api.mkBundle {
            inherit pkgs;
            configuration = toolFixture;
          }).script
        ).success;
      paths =
        map id
          (api.compile {
            extraPackages = [
              toolB
              toolA
              toolB
            ];
            plugins = [
              {
                plugin = a;
                extraPackages = [ toolA ];
              }
            ];
          }).graph.extraPackages;
    };
    expected = {
      plan = false;
      bundle = false;
      paths = [
        (id toolA)
        (id toolB)
      ];
    };
  };
  testGraphvizBuildOnly = {
    expr = (render { plugins = [ ]; }).attrs.nativeBuildInputs;
    expected = [ "graphviz-build-only" ];
  };
  testRejectUnknownRootSchema = invalid {
    plugins = [ ];
    unexpected = true;
  };
  testRejectUnknownNestedSchema = invalid {
    plugins = [
      {
        plugin = a;
        dependPlugins = [
          {
            plugin = b;
            unexpected = true;
          }
        ];
      }
    ];
  };
  testRejectInvalidCallback = invalid {
    plugins = [
      {
        plugin = a;
        config = 42;
      }
    ];
  };
}
