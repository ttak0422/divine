const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const test = require("node:test");

// Isolated event/DOM contract tests, not a substitute for browser rendering QA.
class Element {
  constructor() {
    this.textContent = "";
    this.hidden = false;
    this.disabled = false;
    this.children = [];
    this.events = {};
    this.attrs = {};
    this.style = {};
    this.clientWidth = 800;
    this.clientHeight = 600;
    this.classes = new Set();
    this.classList = {
      toggle: (name, on) => on ? this.classes.add(name) : this.classes.delete(name),
    };
  }
  set innerHTML(_) { throw Error("Unsafe HTML insertion"); }
  setAttribute(key, value) { this.attrs[key] = value; }
  append(element) { this.children.push(element); }
  replaceChildren() { this.children = []; }
  addEventListener(name, handler) { this.events[name] = handler; }
  focus() { this.events.focus?.({}); }
  scrollIntoView() { this.scrolled = true; }
  querySelector() { return this.svg || null; }
  fire(name, event = {}) { this.events[name]?.(event); }
}

const html = fs.readFileSync(path.join(__dirname, "../lib/graph/viewer.html"), "utf8");
const script = fs.readFileSync(path.join(__dirname, "../lib/graph/viewer.js"), "utf8");
function boot(nodes) {
  const elements = Object.fromEntries(
    [...html.matchAll(/id="([^"]+)"/g)].map((match) => [match[1], new Element()]),
  );
  nodes.forEach((node) => { elements[node.svgId] = new Element(); });
  elements["graph-data"].textContent = JSON.stringify({ nodes, units: [], roots: [] });
  const svg = new Element();
  svg.viewBox = { baseVal: { width: 1000, height: 800 } };
  elements["graph-viewport"].svg = svg;
  const document = new Element();
  document.getElementById = (id) => elements[id];
  document.createElement = () => new Element();
  vm.runInNewContext(script, { document });
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
