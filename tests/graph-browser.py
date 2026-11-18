"""Optional real-browser layout regression; needs Playwright and a browser engine.

Build an example with `nix build .#graph`, then run:
    python3 tests/graph-browser.py result [chromium|firefox|webkit]

The Nix/Node checks do not install a browser. This check expands the real
export's SVG viewBox into a synthetic tall diagram to exercise CSS layout.
"""

import json
import os
from pathlib import Path
import re
import sys
import tempfile

from playwright.sync_api import sync_playwright


def tall_diagram(html):
    """Retain the exported nodes/viewer while enlarging the SVG canvas."""
    opening = re.search(r"<svg\b[^>]*>", html, re.DOTALL)
    assert opening is not None, "Expected an exported Graphviz SVG"
    tag = opening.group()
    for key, value in [
        ("width", "1400pt"),
        ("height", "9400pt"),
        ("viewBox", "0 0 1400 9400"),
    ]:
        tag, count = re.subn(rf'\b{key}="[^"]*"', f'{key}="{value}"', tag)
        assert count == 1, f"Expected exactly one SVG {key} attribute"
    return html[: opening.start()] + tag + html[opening.end() :]


def dimensions(page):
    return page.evaluate("""() => {
      const viewport = document.getElementById('graph-viewport');
      return {
        windowHeight: innerHeight,
        bodyHeight: document.documentElement.scrollHeight,
        mainHeight: document.querySelector('main').getBoundingClientRect().height,
        canvasHeight: document.querySelector('.canvas').getBoundingClientRect().height,
        viewportHeight: viewport.clientHeight,
        diagramHeight: viewport.querySelector('svg').getBoundingClientRect().height,
        scrollHeight: viewport.scrollHeight,
        scrollTop: viewport.scrollTop,
        pageScrollTop: scrollY
      };
    }""")


def check_docs(page, data):
    for node in data["nodes"]:
        page.locator(f"#{node['svgId']}").dispatch_event("mouseenter")
        assert page.locator("#doc script, #doc img, #doc svg, #doc iframe, #doc style, #doc input").count() == 0
        assert page.locator("#doc [id], #doc [name], #doc [onload], #doc [onclick]").count() == 0
        for link in page.locator("#doc a").all():
            assert link.get_attribute("href").startswith(("http://", "https://", "mailto:"))
            assert link.get_attribute("rel") == "noopener noreferrer"
        if node["doc"] and node["doc"].startswith("# Alpha documentation"):
            assert page.locator("#doc h1").inner_text() == "Alpha documentation"
            assert page.locator("#doc strong").inner_text() == "Markdown"
            assert page.locator("#doc em").inner_text() == "emphasis"
            assert page.locator("#doc ul ul li").count() == 1
            assert page.locator("#doc ol").get_attribute("start") == "3"
            assert page.locator("#doc blockquote").count() == 1
            assert page.locator("#doc pre code").inner_text() == 'print("<safe code>")\n'
            assert page.locator("#doc a").count() == 3
            text = page.locator("#doc").inner_text()
            assert "[Image: External diagram]" in text
            assert "[Image: Embedded image]" in text
            assert '<svg onload=' in text
            assert '<img src=' in text
    assert page.evaluate("globalThis.graphInjected === undefined")


def check_zoom(page):
    viewport = page.locator("#graph-viewport")
    page.locator("#zoom-reset").click()
    viewport.evaluate("element => { element.scrollLeft = 200; element.scrollTop = 1000; }")
    rect = viewport.bounding_box()
    x, y = rect["x"] + 150, rect["y"] + 150
    page.mouse.move(x, y)
    before = dimensions(page)
    page.mouse.wheel(0, 200)
    page.wait_for_function("() => document.getElementById('graph-viewport').scrollTop > 1000")
    assert page.locator("#zoom-level").inner_text() == "100%"
    assert dimensions(page)["pageScrollTop"] == before["pageScrollTop"]

    page.keyboard.down("Control")
    page.mouse.wheel(0, -100)
    page.keyboard.up("Control")
    page.wait_for_function("() => document.getElementById('zoom-level').textContent !== '100%'")

    # Dispatch deltas in all standard units, checking the same SVG point stays
    # under the pointer. Native trackpad delivery still needs manual testing.
    for mode, delta in [(0, -80), (1, -3), (2, -.2)]:
        result = viewport.evaluate("""(element, args) => {
          const svg = element.querySelector('svg');
          const before = svg.getBoundingClientRect();
          const event = new WheelEvent('wheel', { bubbles: true, cancelable: true,
            ctrlKey: true, clientX: args.x, clientY: args.y, deltaY: args.delta, deltaMode: args.mode });
          const canceled = !element.dispatchEvent(event);
          const after = svg.getBoundingClientRect();
          return { canceled, ratio: after.width / before.width,
            dx: Math.abs((args.x - before.left) / before.width - (args.x - after.left) / after.width),
            dy: Math.abs((args.y - before.top) / before.height - (args.y - after.top) / after.height) };
        }""", {"x": x, "y": y, "delta": delta, "mode": mode})
        assert result["canceled"] and result["ratio"] > 1, result
        assert result["dx"] < .002 and result["dy"] < .002, result

    # Exercise the Safari-specific cumulative-scale path in every engine.
    result = viewport.evaluate("""element => {
      const svg = element.querySelector('svg');
      const before = parseFloat(svg.style.width);
      for (const [type, scale] of [['gesturestart', 1], ['gesturechange', 1.2], ['gesturechange', 1.4], ['gestureend', 1.4]]) {
        const event = new Event(type, { bubbles: true, cancelable: true });
        Object.defineProperties(event, { scale: { value: scale }, clientX: { value: 200 }, clientY: { value: 200 } });
        if (element.dispatchEvent(event)) throw Error('Gesture was not canceled');
      }
      return parseFloat(svg.style.width) / before;
    }""")
    assert abs(result - 1.4) < .001, result
    page.locator("#zoom-out").click()
    page.locator("#zoom-in").click()


html = Path(sys.argv[1]).read_text()
engine = sys.argv[2] if len(sys.argv) > 2 else "chromium"
with tempfile.TemporaryDirectory(prefix="divine-graph-layout-") as temporary:
    fixture = Path(temporary) / "tall.html"
    fixture.write_text(tall_diagram(html))
    with sync_playwright() as playwright:
        options = {"headless": True}
        if os.environ.get("GRAPH_BROWSER_EXECUTABLE"):
            options["executable_path"] = os.environ["GRAPH_BROWSER_EXECUTABLE"]
        browser = getattr(playwright, engine).launch(**options)
        context = browser.new_context(viewport={"width": 1440, "height": 1000})
        # WebKit cannot navigate even a minimal file: page in emulated offline
        # mode. Abort outgoing requests there; the other engines run offline.
        context.set_offline(engine != "webkit")
        context.route("**/*", lambda route: route.continue_()
                      if route.request.url.startswith("file:") else route.abort())
        page = context.new_page()
        errors = []
        requests = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("request", lambda request: requests.append(request.url)
                if request.url != fixture.as_uri() else None)
        page.goto(fixture.as_uri())
        data = json.loads(page.locator("#graph-data").text_content())
        assert data["nodes"], "Use a nonempty graph export"
        before = dimensions(page)
        assert before["canvasHeight"] <= before["mainHeight"] + 1, before
        assert before["diagramHeight"] <= before["viewportHeight"], before
        assert int(page.locator("#zoom-level").inner_text().rstrip("%")) <= 10

        check_docs(page, data)
        check_zoom(page)
        documented = next((node for node in data["nodes"] if node["doc"]), data["nodes"][0])
        page.locator(f"#{documented['svgId']}").dispatch_event("mouseenter")
        inspector = page.locator("aside")
        inspector.evaluate("element => { element.scrollTop = 0; }")
        if inspector.evaluate("element => element.scrollHeight > element.clientHeight"):
            inspector_rect = inspector.bounding_box()
            page.mouse.move(inspector_rect["x"] + 100, inspector_rect["y"] + 200)
            zoom_before_scroll = page.locator("#zoom-level").inner_text()
            graph_scroll = dimensions(page)["scrollTop"]
            page.mouse.wheel(0, 200)
            page.wait_for_function("() => document.querySelector('aside').scrollTop > 0")
            assert page.locator("#zoom-level").inner_text() == zoom_before_scroll
            assert dimensions(page)["scrollTop"] == graph_scroll
        page.locator("#zoom-reset").click()
        page.locator("#graph-viewport").evaluate("element => { element.scrollTop = 1000; }")
        expanded = dimensions(page)
        assert expanded["scrollHeight"] > expanded["viewportHeight"], expanded
        assert expanded["scrollTop"] == 1000, expanded
        assert expanded["pageScrollTop"] == before["pageScrollTop"], expanded
        assert expanded["canvasHeight"] <= expanded["mainHeight"] + 1, expanded

        page.locator("#zoom-fit").click()
        fitted = dimensions(page)
        assert fitted["scrollTop"] == 0, fitted
        assert fitted["diagramHeight"] <= fitted["viewportHeight"], fitted
        page.set_viewport_size({"width": 390, "height": 844})
        page.locator("#zoom-fit").click()
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        assert dimensions(page)["viewportHeight"] <= 844
        assert not errors, errors
        assert not requests, requests
        browser.close()
print(f"{engine}: safe Markdown, zoom gestures, pointer anchoring, ordinary scrolling, Fit, and narrow layout passed.")
