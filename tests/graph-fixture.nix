# Synthetic packages isolate rendering from plugin builds. The punctuation and
# script-like doc are deliberate fixtures for safe text output.
let
  package = name: path: {
    type = "derivation";
    inherit name;
    pname = name;
    outPath = "/nix/store/00000000000000000000000000000000-${path}";
  };
  a = package "shared-name" "alpha";
  b = package "shared-name" "beta";
  c = package "quotes-\"<&>-\\N\tlabel" "gamma";
  d = package "undocumented" "delta";
in
{
  plugins = [
    {
      plugin = a;
      doc = "Alpha documentation\n\n**Markdown** remains literal. 日本語";
      dependPlugins = [ b ];
    }
    {
      plugin = b;
      lazy = true;
      doc = "</script><script>globalThis.graphInjected = true</script><img src=x onerror=alert(1)> & @@GRAPH_SVG@@";
      dependPlugins = [ a ];
    }
    {
      packages = [
        c
        d
        c
      ];
      doc = "Shared configuration documentation";
      dependPlugins = [ a ];
    }
    {
      plugin = c;
      lazy = true;
      doc = "";
      dependPlugins = [ c ];
      tests.notRun = _: throw "graph output must not run checks";
    }
    {
      packages = [
        d
        a
      ];
      lazy = true;
      doc = "Independent overlapping configuration";
    }
  ];
}
