const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const test = require("node:test");

// Isolated event/DOM contract tests, not a substitute for browser rendering QA.
class Element {
  constructor() {
    this._text = "";
    this.hidden = false;
    this.disabled = false;
    this.children = [];
    this.events = {};
    this.attrs = {};
    this.style = {};
    this.clientWidth = 800;
    this.clientHeight = 600;
    this.scrollLeft = 0;
    this.scrollTop = 0;
    this.classes = new Set();
    this.classList = {
      toggle: (name, on) => on ? this.classes.add(name) : this.classes.delete(name),
    };
  }
  get textContent() { return this._text + this.children.map((child) => child.textContent).join(""); }
  set textContent(value) { this._text = value; this.children = []; }
  getBoundingClientRect() { return { left: 0, top: 0 }; }
  set innerHTML(_) { throw Error("Unsafe HTML insertion"); }
  setAttribute(key, value) { this.attrs[key] = value; }
  append(element) { this.children.push(element); }
  replaceChildren() { this._text = ""; this.children = []; }
  addEventListener(name, handler) { this.events[name] = handler; }
  focus() { this.events.focus?.({}); }
  scrollIntoView() { this.scrolled = true; }
  querySelector() { return this.svg || null; }
  fire(name, event = {}) { this.events[name]?.(event); }
}

const html = fs.readFileSync(path.join(__dirname, "../lib/graph/viewer.html"), "utf8");
const script = fs.readFileSync(path.join(__dirname, "../lib/graph/viewer.js"), "utf8");
function boot(nodes, rootTools = []) {
  const elements = Object.fromEntries(
    [...html.matchAll(/id="([^"]+)"/g)].map((match) => [match[1], new Element()]),
  );
  nodes.forEach((node) => { elements[node.svgId] = new Element(); });
  elements["graph-data"].textContent = JSON.stringify({ nodes, units: [], roots: [], rootExtraPackageNames: rootTools });
  const svg = new Element();
  svg.viewBox = { baseVal: { width: 1000, height: 800 } };
  elements["graph-viewport"].svg = svg;
  const document = new Element();
  document.getElementById = (id) => elements[id];
  document.createElement = (tag) => { const element = new Element(); element.tag = tag; return element; };
  document.createTextNode = (value) => { const element = new Element(); element.textContent = value; return element; };
  vm.runInNewContext(script, { document, URL });
  return { elements, document, svg };
}

const packageNode = {
  id: "/nix/store/a", svgId: "graph-node-0", label: "Same", kind: "package",
  doc: "<img src=x onerror=alert(1)>", origins: ["plugins[0]"], dependencies: [],
  members: [], root: true, unitId: "a", unitStartup: false, cyclic: false,
  physicalStartup: true,
};
const groupNode = {
  ...packageNode, id: "group:1", svgId: "graph-node-1", kind: "configuration",
  doc: null, members: [packageNode.id], dependencies: [packageNode.id],
};

test("runtime tools are separate, text-only lists in the inspector", () => {
  const label = "<img src=x onerror=alert(1)>";
  const { elements: e } = boot([{ ...packageNode, extraPackageNames: [label] }, groupNode], ["global-tool"]);
  assert.equal(e["root-tools-section"].hidden, false);
  assert.equal(e["root-tools"].textContent, "global-tool");
  e[packageNode.svgId].fire("mouseenter");
  assert.equal(e["node-tools-section"].hidden, false);
  assert.equal(e["node-tools"].children[0].textContent, label);
  assert.equal(e["node-tools"].children[0].children.length, 0);
  assert.equal(e.dependencies.textContent, "None");
  e[groupNode.svgId].fire("mouseenter");
  assert.equal(e["node-tools-section"].hidden, true);
});

test("hover and focus show text-safe docs, identities, membership and startup distinctions", () => {
  const { elements: e } = boot([packageNode, groupNode]);
  e[packageNode.svgId].fire("mouseenter");
  assert.equal(e.doc.textContent, packageNode.doc);
  assert.match(e.startup.textContent, /does not imply a standalone startup declaration/);
  e[groupNode.svgId].fire("focus");
  assert.equal(e.identity.textContent, groupNode.id);
  assert.match(e.doc.textContent, /No documentation/);
  assert.equal(e["members-section"].hidden, false);
  assert.equal(e.members.children.length, 1);
  assert.equal(e.dependencies.children.length, 1);
  assert.equal(e[groupNode.svgId].attrs.role, "button");
  assert.equal(e[groupNode.svgId].attrs.tabindex, "0");
});

test("click and keyboard pin details until Escape or Clear pin", () => {
  const { elements: e, document } = boot([packageNode, groupNode]);
  e[packageNode.svgId].fire("click");
  e[groupNode.svgId].fire("mouseenter");
  e[groupNode.svgId].fire("focus");
  assert.equal(e.identity.textContent, packageNode.id);
  document.fire("keydown", { key: "Escape" });
  e[groupNode.svgId].fire("focus");
  assert.equal(e.identity.textContent, groupNode.id);
  e[packageNode.svgId].fire("keydown", { key: " ", preventDefault() {} });
  assert.equal(e.identity.textContent, packageNode.id);
  assert.equal(e[packageNode.svgId].attrs["aria-pressed"], "true");
  e["clear-selection"].fire("click");
  e[groupNode.svgId].fire("focus");
  assert.equal(e.identity.textContent, groupNode.id);
  e[groupNode.svgId].fire("keydown", { key: "Enter", preventDefault() {} });
  assert.equal(e[groupNode.svgId].attrs["aria-pressed"], "true");
});

test("search matches docs and IDs, dims without removal, and Enter reveals the next match", () => {
  const { elements: e } = boot([packageNode, groupNode]);
  e.search.fire("input", { target: { value: "onerror" } });
  assert.equal(e["search-status"].textContent, "1 match");
  assert.equal(e[groupNode.svgId].classes.has("dimmed"), true);
  e["next-match"].fire("click");
  assert.equal(e.identity.textContent, packageNode.id);
  assert.equal(e[packageNode.svgId].scrolled, true);
  e.search.fire("input", { target: { value: "group:1" } });
  let prevented = false;
  e.search.fire("keydown", { key: "Enter", preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(e.identity.textContent, groupNode.id);
  e.search.fire("input", { target: { value: "missing" } });
  assert.equal(e["next-match"].disabled, true);
  e.search.fire("input", { target: { value: "" } });
  assert.equal(e[groupNode.svgId].classes.has("dimmed"), false);
  assert.equal(e[packageNode.svgId].classes.has("dimmed"), false);
});

test("fit respects viewport dimensions, zoom changes scale and reset restores 100%", () => {
  const { elements: e, svg } = boot([packageNode]);
  e["zoom-fit"].fire("click");
  assert.ok(parseFloat(svg.style.width) <= 752);
  assert.ok(parseFloat(svg.style.height) <= 552);
  const before = parseFloat(svg.style.width);
  e["zoom-in"].fire("click");
  assert.ok(parseFloat(svg.style.width) > before);
  e["zoom-out"].fire("click");
  assert.ok(Math.abs(parseFloat(svg.style.width) - before) < .001);
  e["zoom-reset"].fire("click");
  assert.equal(e["zoom-level"].textContent, "100%");
});

test("empty graphs show an explanation and disable irrelevant controls", () => {
  const { elements: e } = boot([]);
  assert.equal(e["empty-graph"].hidden, false);
  assert.equal(e["graph-viewport"].hidden, true);
  assert.equal(e["zoom-in"].disabled, true);
  assert.equal(e.search.disabled, true);
});

// CSS Grid's automatic minimum otherwise lets a tall SVG expand the row and
// makes Fit measure the diagram's height instead of the visible viewport.
test("canvas can shrink inside the fixed-height graph row", () => {
  assert.match(html, /\.canvas\s*\{[^}]*min-height:\s*0\s*;/);
});


test("Ctrl wheel zooms at the pointer, normal scrolling and uncancelable events stay native", () => {
  const { elements: e, svg } = boot([packageNode]);
  const viewport = e["graph-viewport"];
  let prevented = 0;
  const wheel = { deltaY: -100, deltaMode: 0, clientX: 200, clientY: 150, cancelable: true, preventDefault() { prevented++; } };
  const before = parseFloat(svg.style.width);
  viewport.fire("wheel", wheel);
  assert.equal(prevented, 0);
  assert.equal(parseFloat(svg.style.width), before);
  viewport.fire("wheel", { ...wheel, ctrlKey: true, cancelable: false });
  assert.equal(parseFloat(svg.style.width), before);
  viewport.fire("wheel", { ...wheel, ctrlKey: true });
  assert.equal(prevented, 1);
  assert.ok(parseFloat(svg.style.width) > before);
  assert.ok(Math.abs(viewport.scrollLeft - 200 * (Math.exp(.2) - 1)) < .001);
  assert.ok(Math.abs(viewport.scrollTop - 150 * (Math.exp(.2) - 1)) < .001);
  for (const deltaMode of [1, 2]) {
    viewport.fire("wheel", { ...wheel, deltaMode, ctrlKey: true, deltaY: -100000 });
    assert.ok(parseFloat(svg.style.width) <= 1000 * 4 / 3 * 5);
  }
  for (let i = 0; i < 20; i++) viewport.fire("wheel", { ...wheel, ctrlKey: true, deltaY: -100000 });
  assert.equal(e["zoom-level"].textContent, "500%");
  for (let i = 0; i < 20; i++) viewport.fire("wheel", { ...wheel, ctrlKey: true, deltaY: 100000 });
  assert.equal(e["zoom-level"].textContent, "2%");
  viewport.fire("wheel", { ...wheel, ctrlKey: true, deltaY: NaN });
  assert.ok(Number.isFinite(parseFloat(svg.style.width)));
});

test("Safari pinch uses cumulative scale and avoids simultaneous wheel zoom", () => {
  const { elements: e, svg } = boot([packageNode]);
  const viewport = e["graph-viewport"];
  const gesture = { cancelable: true, clientX: 200, clientY: 150, preventDefault() {} };
  const before = parseFloat(svg.style.width);
  viewport.fire("gesturestart", gesture);
  viewport.fire("gesturechange", { ...gesture, scale: 1.5 });
  assert.equal(parseFloat(svg.style.width), before * 1.5);
  viewport.fire("wheel", { ...gesture, ctrlKey: true, deltaY: -100 });
  assert.equal(parseFloat(svg.style.width), before * 1.5);
  viewport.fire("gesturechange", { ...gesture, scale: 2 });
  assert.equal(parseFloat(svg.style.width), before * 2);
  viewport.fire("gestureend", gesture);
  viewport.fire("gesturechange", { ...gesture, scale: 3 });
  assert.equal(parseFloat(svg.style.width), before * 2);
});

test("documentation tokens create safe elements with inert images and unsafe links", () => {
  const token = (type, tag, nesting, content = "", attrs = {}) => ({ type, tag, nesting, content, attrs });
  const docTokens = [
    token("heading_open", "h1", 1), token("text", "", 0, "Heading"), token("heading_close", "h1", -1),
    token("fence", "code", 0, "<script>alert(1)</script>"),
    token("image", "img", 0, "diagram", { src: "https://example.com/tracker" }),
    ...["javascript:alert(1)", "data:text/html,evil", "file:///tmp/secret", "//example.com", "relative.md", "https://example.com/docs"].flatMap((href) => [
      token("link_open", "a", 1, "", { href, onclick: "alert(1)" }), token("text", "", 0, "link"), token("link_close", "a", -1),
    ]),
  ];
  const { elements: e } = boot([{ ...packageNode, docTokens }]);
  e[packageNode.svgId].fire("mouseenter");
  assert.equal(e.doc.children[0].tag, "h1");
  assert.equal(e.doc.children[1].children[0].tag, "code");
  assert.match(e.doc.textContent, /<script>alert\(1\)<\/script>/);
  assert.match(e.doc.textContent, /\[Image: diagram\]/);
  assert.equal(e.doc.children.filter((element) => element.tag === "a").length, 1);
  const link = e.doc.children.at(-1);
  assert.equal(link.href, "https://example.com/docs");
  assert.equal(link.rel, "noopener noreferrer");
  assert.equal(link.onclick, undefined);
});
