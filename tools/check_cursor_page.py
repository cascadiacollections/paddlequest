"""Run the embed document's cursor function under Node.

The dot lives in a JavaScript string inside addons/xr_webview/xr_web_panel.gd.
This extracts that function and runs it against a stub document, which is as
close as CI can get to the page without a headset.

    python3 tools/check_cursor_page.py
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PANEL = ROOT / "addons" / "xr_webview" / "xr_web_panel.gd"

NODE_RUNNER = r"""
const fs = require("fs");
const source = fs.readFileSync(process.argv[2], "utf8");
const cases = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const runner = new Function(
  "document",
  "innerWidth",
  "innerHeight",
  "u",
  "v",
  source + "\nxrCursor(u, v);\n"
);
const results = [];
for (const c of cases) {
  const style = {};
  const document = {
    getElementById(id) {
      if (c.missing) return null;
      if (id !== "xr-cursor") return null;
      return { style };
    },
  };
  let error = null;
  try {
    runner(document, c.w, c.h, c.u, c.v);
  } catch (err) {
    error = String(err);
  }
  results.push({
    display: Object.prototype.hasOwnProperty.call(style, "display") ? style.display : null,
    transform: Object.prototype.hasOwnProperty.call(style, "transform") ? style.transform : null,
    error,
  });
}
process.stdout.write(JSON.stringify(results));
"""


def _panel_source() -> str:
    return PANEL.read_text()


def embed_template(source: str) -> str:
    match = re.search(r'const EMBED_TEMPLATE := """(.*?)"""', source, re.S)
    if match is None:
        sys.exit(f"EMBED_TEMPLATE not found in {PANEL}")
    return match.group(1)


def cursor_function(template: str) -> str:
    start = template.find("function xrCursor")
    if start < 0:
        sys.exit("xrCursor() is missing from EMBED_TEMPLATE")
    brace = template.find("{", start)
    depth = 0
    for index in range(brace, len(template)):
        char = template[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return template[start : index + 1]
    sys.exit("xrCursor() has no closing brace")


def _fail(message: str) -> None:
    sys.exit(message)


def check_markup(template: str) -> None:
    source = _panel_source()
    diameter = re.search(r"const CURSOR_DIAMETER_PX := ([0-9.]+)", source)
    if diameter is None or float(diameter.group(1)) != 14.0:
        _fail("CURSOR_DIAMETER_PX must stay 14.0, matching the embed template")
    element = re.search(r'<div id="xr-cursor"[^>]*>', template)
    if element is None:
        _fail("the embed template has no xr-cursor element")
    tag = element.group(0)
    for needle in (
        "pointer-events:none",
        "position:fixed",
        "width:14px",
        "height:14px",
        "margin:-7px 0 0 -7px",
        "z-index:2147483647",
    ):
        if needle not in tag:
            _fail(f"xr-cursor element is missing {needle}")
    body = template.replace("%s", "")
    if "%" in body or "#" in body:
        _fail("EMBED_TEMPLATE gained a '#' or a '%' outside the format specifier")


def run_cases(function: str) -> None:
    node = shutil.which("node")
    if node is None:
        _fail("node is required to run the embed cursor (it is on the CI image)")
    cases = [
        {
            "w": 640,
            "h": 360,
            "u": 0.25,
            "v": 0.5,
            "display": "block",
            "transform": "translate(160px,180px)",
        },
        {
            "w": 640,
            "h": 360,
            "u": 0,
            "v": 0,
            "display": "block",
            "transform": "translate(0px,0px)",
        },
        {
            "w": 640,
            "h": 360,
            "u": 1,
            "v": 1,
            "display": "block",
            "transform": "translate(640px,360px)",
        },
        {"w": 640, "h": 360, "u": -1, "v": -1, "display": "none", "transform": None},
        {
            "w": 1280,
            "h": 720,
            "u": 0.5,
            "v": 0.25,
            "display": "block",
            "transform": "translate(640px,180px)",
        },
        {
            "w": 640,
            "h": 360,
            "u": 0.5,
            "v": 0.5,
            "missing": True,
            "display": None,
            "transform": None,
        },
    ]
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "runner.js").write_text(NODE_RUNNER)
        (root / "cursor.js").write_text(function)
        (root / "cases.json").write_text(json.dumps(cases))
        completed = subprocess.run(
            [
                node,
                str(root / "runner.js"),
                str(root / "cursor.js"),
                str(root / "cases.json"),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
    if completed.returncode != 0:
        _fail(completed.stderr.strip() or "node failed while running xrCursor()")
    results = json.loads(completed.stdout)
    if len(results) != len(cases):
        _fail(f"expected {len(cases)} results, got {len(results)}")
    for case, result in zip(cases, results):
        if result["error"]:
            _fail(f"xrCursor({case['u']}, {case['v']}) threw {result['error']}")
        if (
            result["display"] != case["display"]
            or result["transform"] != case["transform"]
        ):
            _fail(f"xrCursor({case['u']}, {case['v']}) -> {result}, expected {case}")


def main() -> None:
    template = embed_template(_panel_source())
    check_markup(template)
    run_cases(cursor_function(template))
    print("embed cursor matches the stub page")


if __name__ == "__main__":
    main()
