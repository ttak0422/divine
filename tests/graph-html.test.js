// Validate generated artifacts, including the JSON/HTML boundary and SVG IDs.
const assert = require("node:assert/strict");
const fs = require("node:fs");

function read(path) {
  const html = fs.readFileSync(path, "utf8");
  const match = html.match(/<script id="graph-data" type="application\/json">([\s\S]*?)<\/script>/);
  assert.ok(match, "embedded graph data exists");
  assert.equal((html.match(/<script\b/g) || []).length, 2, "only data and viewer scripts exist");
  assert.equal((html.match(/<\/script>/g) || []).length, 2, "docs cannot close script elements");
  assert.ok(!/[<>&]/.test(match[1]), "raw-text data is escaped");
  assert.ok(!/<(?:script|link|img|iframe)\b[^>]*(?:src|href)=/i.test(html), "no external assets");
  assert.ok(html.includes("default-src 'none'"), "restrict network access");
  assert.ok(html.includes("<svg"), "actual Graphviz SVG is embedded");
  const data = JSON.parse(match[1]);
  assert.equal(data.nodes.length, new Set(data.nodes.map((n) => n.id)).size, "node identities are unique");
  for (const node of data.nodes) {
    const decoded = html.replace(/&#(x[0-9a-f]+|[0-9]+);/gi, (_, code) => String.fromCodePoint(code[0].toLowerCase() === "x" ? parseInt(code.slice(1), 16) : Number(code)));
    assert.equal(decoded.split(`id="${node.svgId}"`).length, 2, "each node has exactly one SVG element");
  }
  return { html, data };
}

const { html, data } = read(process.argv[2]);
const decodedSvg = html.split('<script')[0]
  .replace(/&#(x[0-9a-f]+|[0-9]+);/gi, (_, code) => String.fromCodePoint(code[0].toLowerCase() === "x" ? parseInt(code.slice(1), 16) : Number(code)))
  .replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
assert.ok(decodedSvg.includes('quotes-"<&>-\\N label'), "DOT labels normalize tab spacing without changing literal punctuation");
assert.equal(data.nodes.length, 6);
assert.equal(data.nodes.filter((n) => n.label === "shared-name").length, 2);
assert.equal(data.nodes.filter((n) => n.cyclic).length, 3);
assert.equal(data.nodes.find((n) => n.label === "undocumented").doc, null);
assert.equal(data.nodes.find((n) => n.id.endsWith("-gamma")).doc, "");
assert.ok(data.nodes.some((n) => n.doc && n.doc.includes("</script><script>globalThis.graphInjected")));
assert.ok(data.nodes.some((n) => n.doc && n.doc.includes("@@GRAPH_SVG@@")));
assert.equal(data.nodes.filter((n) => n.kind === "configuration").length, 2);
assert.deepEqual(read(process.argv[3]).data.nodes, []);
console.log("Generated graph HTML: identity, cycles, groups, escaping and empty graph passed.");
