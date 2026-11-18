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
      doc = ''
        # Alpha documentation

        **Markdown** and *emphasis*. 日本語

        - First item
          - Nested item with `inline code`
        - Second item

        3. Ordered item
        4. Another item

        > A quoted paragraph.

        ```lua
        print("<safe code>")
        ```

        [Project docs](https://example.com/docs "Project")
        [Reference link][reference]
        [Email](mailto:docs@example.com)

        [reference]: https://example.com/reference

        ![External diagram](https://example.com/tracking.png)
        ![Embedded image](data:image/png;base64,AAAA)
        [Unsafe](javascript:alert(1))
        [Encoded](jav&#x61;script:alert(1))
        [Data](data:text/html,evil)
        [Local](file:///etc/passwd)
        [Relative](./docs.md)
        [Protocol relative](//example.com/path)
        <svg onload="globalThis.graphInjected = true"></svg>
        <iframe src="https://example.com/frame"></iframe>
        <img src="https://example.com/raw.png" onerror="globalThis.graphInjected = true">
      '';
      dependPlugins = [ b ];
    }
    {
      plugin = b;
      lazy = true;
      doc = "</script><script>globalThis.graphInjected = true</script><img src=x onerror=alert(1)> & @@GRAPH_SVG@@ @@GRAPH_DATA@@ @@GRAPH_SCRIPT@@";
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
