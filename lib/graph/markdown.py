"""Parse docs at build time; keep the offline viewer free of parser dependencies."""

import json
from pathlib import Path
import sys

from markdown_it import MarkdownIt


def tokens(source):
    def serialize(token):
        return {
            "type": token.type,
            "tag": token.tag,
            "nesting": token.nesting,
            "content": token.content,
            "attrs": token.attrs,
            "hidden": token.hidden,
            "children": [serialize(child) for child in token.children or []],
        }

    return [serialize(token) for token in MarkdownIt("commonmark", {"html": False}).parse(source)]


if __name__ == "__main__":
    data = json.loads(Path(sys.argv[1]).read_text())
    for node in data["nodes"]:
        node["docTokens"] = tokens(node["doc"] or "")
    # JSON script elements are raw-text contexts, including application/json.
    encoded = json.dumps(data).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    sys.stdout.write(Path(sys.argv[2]).read_text().replace("@@GRAPH_DATA@@", encoded))
