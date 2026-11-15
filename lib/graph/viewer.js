/* Standalone viewer: untrusted content uses DOM elements, never HTML insertion. */
(() => {
  "use strict";
  const get = (id) => document.getElementById(id);
  const data = JSON.parse(get("graph-data").textContent);
  const nodes = data.nodes;
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const elements = new Map(nodes.map((node) => [node.id, get(node.svgId)]));
  const viewport = get("graph-viewport");
  const svg = viewport.querySelector("svg");
  let pinned = null;
  let current = null;
  let matches = [];
  let matchIndex = -1;

  const setText = (id, value) => { get(id).textContent = value; };
  const fillList = (id, values, linkNodes) => {
    const list = get(id);
    list.replaceChildren();
    if (!values.length) values = ["None"];
    for (const value of values) {
      const li = document.createElement("li");
      const node = linkNodes && byId.get(value);
      if (node) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "node-link";
        button.textContent = node.label;
        const identity = document.createElement("span");
        identity.className = "node-identity";
        identity.textContent = node.id;
        button.append(identity);
        button.addEventListener("click", () => select(node, true, true));
        li.append(button);
      } else li.textContent = value;
      list.append(li);
    }
  };
  // Only these parser tags and explicitly checked attributes may reach the DOM.
  const docTags = new Set(["p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "em", "strong", "a", "code", "hr", "br"]);
  const renderDoc = (parent, tokens) => {
    const stack = [parent];
    for (const token of tokens) {
      if (token.hidden) continue;
      if (token.nesting === -1) { stack.pop(); continue; }
      const container = stack[stack.length - 1];
      if (token.type === "inline") { renderDoc(container, token.children); continue; }
      if (token.type === "softbreak") { container.append(document.createTextNode("\n")); continue; }
      if (token.type === "fence" || token.type === "code_block") {
        const pre = document.createElement("pre");
        const code = document.createElement("code");
        code.textContent = token.content;
        pre.append(code);
        container.append(pre);
        continue;
      }
      if (!docTags.has(token.tag)) {
        container.append(document.createTextNode(token.type === "image" ? `[Image: ${token.content}]` : token.content));
        continue;
      }
      const element = document.createElement(token.tag === "a" ? "span" : token.tag);
      if (token.tag === "a") {
        const href = token.attrs.href || "";
        // No base URL: relative, protocol-relative and file links stay inert.
        let url;
        try { url = new URL(href); } catch {}
        if (url && ["http:", "https:", "mailto:"].includes(url.protocol)) {
          const link = document.createElement("a");
          link.href = url.href;
          link.target = "_blank";
          link.rel = "noopener noreferrer";
          container.append(link);
          stack.push(link);
          continue;
        }
      }
      if (token.tag === "ol" && Number.isInteger(token.attrs.start)) element.start = token.attrs.start;
      if (!token.nesting) element.textContent = token.content;
      container.append(element);
      if (token.nesting === 1) stack.push(element);
    }
  };
  const render = (node) => {
    current = node;
    get("inspector-empty").hidden = !!node;
    get("inspector-content").hidden = !node;
    get("clear-selection").disabled = !pinned;
    setText("selection-mode", pinned ? "Pinned · Escape or Clear pin to resume previews." : "Hover or focus a node to inspect it. Click to pin.");
    for (const [id, element] of elements) {
      if (!element) continue;
      element.classList.toggle("selected", !!node && id === node.id);
      element.setAttribute("aria-pressed", String(!!pinned && id === pinned.id));
    }
    if (!node) return;
    setText("node-label", node.label);
    setText("identity-heading", node.kind === "package" ? "Package output identity" : "Configuration occurrence ID · internal, not stable");
    setText("identity", node.id);
    get("doc").replaceChildren();
    if (node.docTokens?.length) renderDoc(get("doc"), node.docTokens);
    else setText("doc", node.doc === null || node.doc === undefined ? "No documentation supplied for this node." : node.doc === "" ? "Documentation is an empty string." : node.doc);
    setText("unit-id", node.unitId);
    const unitText = node.unitStartup ? "This configuration's load unit is required at startup." : "This configuration's load unit is not required at startup.";
    const packageText = node.kind === "package" ? (node.physicalStartup ? " The physical package is loaded at startup by at least one unit; this does not imply a standalone startup declaration." : " The physical package is not required at startup.") : " Group members have their own physical package identities; membership does not declare singleton startup demand.";
    setText("startup", unitText + packageText);
    get("badges").replaceChildren();
    for (const label of [node.kind === "package" ? "Package" : "Configuration group", node.root && "Root", node.cyclic && "Cyclic unit"]) {
      if (!label) continue;
      const badge = document.createElement("span");
      badge.className = "badge";
      badge.textContent = label;
      get("badges").append(badge);
    }
    fillList("dependencies", node.dependencies, true);
    fillList("origins", node.origins, false);
    get("members-section").hidden = node.kind !== "configuration";
    fillList("members", node.members, true);
  };
  const select = (node, pin, reveal = false) => {
    if (!pin && pinned) return;
    if (pin) pinned = node;
    render(node);
    if (reveal) {
      const element = elements.get(node.id);
      if (element) {
        element.focus({ preventScroll: true });
        element.scrollIntoView({ block: "nearest", inline: "nearest" });
      }
    }
  };
  const clearPin = () => { pinned = null; render(current); };
  for (const node of nodes) {
    const element = elements.get(node.id);
    if (!element) continue;
    // Replace Graphviz's internal n0-style tooltip with the display label.
    const title = element.querySelector("title");
    if (title) title.textContent = node.label;
    element.setAttribute("tabindex", "0");
    element.setAttribute("role", "button");
    element.setAttribute("aria-label", `${node.label}, ${node.kind}, ${node.id}. Press Enter to pin details.`);
    element.setAttribute("aria-pressed", "false");
    element.addEventListener("mouseenter", () => select(node, false));
    element.addEventListener("focus", () => select(node, false));
    element.addEventListener("click", () => select(node, true));
    element.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        select(node, true);
      }
    });
  }
  get("clear-selection").addEventListener("click", clearPin);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") clearPin();
  });
  const nextMatch = () => {
    if (!matches.length) return;
    matchIndex = (matchIndex + 1) % matches.length;
    select(matches[matchIndex], true, true);
    setText("search-status", `${matchIndex + 1} of ${matches.length} matches`);
  };
  get("search").addEventListener("input", (event) => {
    const query = event.target.value.trim().toLocaleLowerCase();
    matches = query ? nodes.filter((node) => [node.label, node.id, node.doc || ""].some((value) => value.toLocaleLowerCase().includes(query))) : [];
    matchIndex = -1;
    const matchingIds = new Set(matches.map((node) => node.id));
    for (const [id, element] of elements) {
      if (element) element.classList.toggle("dimmed", !!query && !matchingIds.has(id));
    }
    get("next-match").disabled = !matches.length;
    setText("search-status", query ? `${matches.length} ${matches.length === 1 ? "match" : "matches"}` : "");
  });
  get("next-match").addEventListener("click", nextMatch);
  get("search").addEventListener("keydown", (event) => {
    if (event.key === "Enter") { event.preventDefault(); nextMatch(); }
  });

  // Graphviz's viewBox uses points. Convert to CSS pixels for natural scale.
  let zoom = 1;
  const box = svg && svg.viewBox.baseVal;
  const width = box && box.width > 0 ? box.width * 4 / 3 : 1;
  const height = box && box.height > 0 ? box.height * 4 / 3 : 1;
  const setZoom = (value, clientX, clientY) => {
    if (!Number.isFinite(value)) return;
    const previous = zoom;
    const rect = svg && svg.getBoundingClientRect();
    zoom = Math.max(.02, Math.min(5, value));
    if (svg) { svg.style.width = `${width * zoom}px`; svg.style.height = `${height * zoom}px`; }
    if (rect && Number.isFinite(clientX) && Number.isFinite(clientY)) {
      viewport.scrollLeft += (clientX - rect.left) * (zoom / previous - 1);
      viewport.scrollTop += (clientY - rect.top) * (zoom / previous - 1);
    }
    setText("zoom-level", `${Math.round(zoom * 100)}%`);
  };
  const fit = () => { setZoom(Math.min(1, Math.max(1, viewport.clientWidth - 48) / width, Math.max(1, viewport.clientHeight - 48) / height)); viewport.scrollTop = 0; viewport.scrollLeft = 0; };
  get("zoom-in").addEventListener("click", () => setZoom(zoom * 1.25));
  get("zoom-out").addEventListener("click", () => setZoom(zoom / 1.25));
  get("zoom-reset").addEventListener("click", () => setZoom(1));
  get("zoom-fit").addEventListener("click", fit);
  let gestureZoom = null;
  viewport.addEventListener("wheel", (event) => {
    if (!nodes.length || !event.ctrlKey || !event.cancelable) return;
    event.preventDefault();
    if (gestureZoom !== null) return;
    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? viewport.clientHeight : 1;
    const delta = Math.max(-300, Math.min(300, event.deltaY * unit));
    setZoom(zoom * Math.exp(-delta * .002), event.clientX, event.clientY);
  }, { passive: false });
  // Safari exposes trackpad pinch as GestureEvent rather than Ctrl + wheel.
  viewport.addEventListener("gesturestart", (event) => {
    if (!nodes.length || !event.cancelable) return;
    event.preventDefault();
    gestureZoom = zoom;
  }, { passive: false });
  viewport.addEventListener("gesturechange", (event) => {
    if (gestureZoom === null || !event.cancelable) return;
    event.preventDefault();
    if (event.scale > 0) setZoom(gestureZoom * event.scale, event.clientX, event.clientY);
  }, { passive: false });
  viewport.addEventListener("gestureend", (event) => {
    if (gestureZoom === null) return;
    if (event.cancelable) event.preventDefault();
    gestureZoom = null;
  }, { passive: false });
  setText("graph-summary", `${nodes.length} nodes · ${data.units.length} load units · ${data.roots.length} roots`);
  if (!nodes.length) {
    get("empty-graph").hidden = false;
    viewport.hidden = true;
    for (const id of ["zoom-in", "zoom-out", "zoom-reset", "zoom-fit", "search"]) get(id).disabled = true;
  }
  fit();
})();
