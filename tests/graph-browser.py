"""Optional real-browser layout regression; needs Playwright and Chromium.

Build an example with `nix build .#graph`, then run:
    python3 tests/graph-browser.py result

The Nix/Node checks do not install a browser. This check expands the real
export's SVG viewBox into a synthetic tall diagram to exercise CSS layout.
"""

import json
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


html = Path(sys.argv[1]).read_text()
with tempfile.TemporaryDirectory(prefix="divine-graph-layout-") as temporary:
    fixture = Path(temporary) / "tall.html"
    fixture.write_text(tall_diagram(html))
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(viewport={"width": 1440, "height": 1000})
        context.set_offline(True)
        page = context.new_page()
        errors = []
        requests = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("request", lambda request: requests.append(request.url)
                if not request.url.startswith("file:") else None)
        page.goto(fixture.as_uri())
        data = json.loads(page.locator("#graph-data").text_content())
        assert data["nodes"], "Use a nonempty graph export"
        before = dimensions(page)
        assert before["canvasHeight"] <= before["mainHeight"] + 1, before
        assert before["diagramHeight"] <= before["viewportHeight"], before
        assert int(page.locator("#zoom-level").inner_text().rstrip("%")) <= 10

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
print("Tall SVG: viewport containment, Fit, inner scrolling, and narrow layout passed.")
