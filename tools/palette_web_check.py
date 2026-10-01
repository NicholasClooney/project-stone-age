#!/usr/bin/env python3
"""Checks the palette sheet shader on a real GPU without opening a window.

Builds a small Godot web project (client/scripts/palette_sheet.gd, the node
client/tests/perf/palette_render_check.gd and sample sheets), exports it with
the project's web templates, serves it on 127.0.0.1 and runs it in headless
Chromium (WebGL 2, the renderer phones and Vision Pro use). Prints the
check's output and exits 1 unless it reports 0 failures.

  npm install --prefix <scratch> playwright-core
  python3 tools/palette_web_check.py --modules <scratch> --chrome <chrome binary> \
      [sheet.png ...]

Without sheets it takes the two smallest and one mid-sized sheet of each
folder in palette_sheet.gd's KINDS. See docs/technical/palette-textures.md.
"""
import argparse
import functools
import http.server
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLIENT = ROOT / "client"
LEGACY = CLIENT / "assets/legacy"

PROJECT = """config_version=5
[application]
config/name="Palette check"
run/main_scene="res://check.tscn"
config/features=PackedStringArray("4.6", "GL Compatibility")
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
"""
SCENE = """[gd_scene format=3]
[ext_resource type="Script" path="res://tests/perf/palette_render_check.gd" id="1"]
[node name="Check" type="Node"]
script = ExtResource("1")
"""
PRESET_KEYS = ("include_filter", "exclude_filter", "export_path", "html/head_include")

RUNNER = r"""
const { createRequire } = require("node:module");
const [modules, chrome, url, angle] = process.argv.slice(2);
const { chromium } = createRequire(modules + "/package.json")("playwright-core");
(async () => {
  const browser = await chromium.launch({ executablePath: chrome, headless: true,
    args: angle === "metal" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"]
      : ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
  const page = await browser.newPage();
  let done;
  const finished = new Promise((resolve) => (done = resolve));
  page.on("console", (message) => {
    const text = message.text();
    console.log(text);
    if (text.startsWith("palette_render_check:")) done(text);
  });
  page.on("pageerror", (error) => console.log("PAGE ERROR " + error));
  await page.goto(url);
  console.log("WebGL renderer: " + await page.evaluate(() => {
    const gl = document.createElement("canvas").getContext("webgl2");
    const info = gl && gl.getExtension("WEBGL_debug_renderer_info");
    return info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : "unknown";
  }));
  const timeout = new Promise((resolve) => setTimeout(() => resolve("timeout"), 600000));
  const result = await Promise.race([finished, timeout]);
  await browser.close();
  process.exit(result === "palette_render_check: 0 failures" ? 0 : 1);
})();
"""


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def godot():
    for candidate in (ROOT / ".tools/Godot.app/Contents/MacOS/Godot", shutil.which("godot")):
        if candidate and Path(candidate).exists():
            return str(candidate)
    sys.exit("Godot not found (.tools/Godot.app)")


def kinds_folders():
    text = (CLIENT / "scripts/palette_sheet.gd").read_text()
    block = re.search(r"const KINDS := \{(.*?)\n\}", text, re.S).group(1)
    return re.findall(r'"[a-z]+":"([^"]+)"', block)


def samples():
    chosen = []
    for folder in kinds_folders():
        sheets = sorted((LEGACY / folder).glob("*.png"), key=lambda p: (p.stat().st_size, p.name))
        picks = sheets[:2] + ([sheets[len(sheets) // 2]] if len(sheets) > 2 else [])
        chosen += picks
    return chosen


def web_preset():
    """The project's Web preset with the filters and paths this export needs."""
    text = (CLIENT / "export_presets.cfg").read_text()
    lines = []
    for line in text.splitlines():
        key = line.split("=", 1)[0]
        if key in PRESET_KEYS:
            continue
        lines.append(line)
        if line == "[preset.0]":
            lines += ['include_filter="sheets/*"', 'exclude_filter=""', 'export_path="out/index.html"']
    return "\n".join(lines) + "\n"


def build(project, sheets):
    (project / "scripts").mkdir(parents=True)
    (project / "tests/perf").mkdir(parents=True)
    (project / "sheets").mkdir()
    shutil.copy(CLIENT / "scripts/palette_sheet.gd", project / "scripts/")
    shutil.copy(CLIENT / "tests/perf/palette_render_check.gd", project / "tests/perf/")
    (project / "project.godot").write_text(PROJECT)
    (project / "check.tscn").write_text(SCENE)
    (project / "export_presets.cfg").write_text(web_preset())
    names = []
    for index, sheet in enumerate(sheets):
        # Not .png, so Godot keeps the bytes instead of importing a texture.
        name = f"res://sheets/{index:02d}-{sheet.parent.parent.name}-{sheet.stem}.sheet"
        shutil.copy(sheet, project / name[len("res://"):])
        names.append(name)
    (project / "sheets/list.txt").write_text("\n".join(names) + "\n")
    (project / "out").mkdir()
    subprocess.run([godot(), "--headless", "--path", str(project), "--import"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run([godot(), "--headless", "--path", str(project), "--export-debug", "Web",
                             str(project / "out/index.html")], capture_output=True, text=True)
    if not (project / "out/index.html").exists():
        sys.exit("export failed:\n" + result.stdout[-2000:] + result.stderr[-2000:])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--modules", required=True, help="folder playwright-core was installed into")
    parser.add_argument("--chrome", required=True, help="Chromium executable")
    parser.add_argument("--keep", action="store_true", help="keep the temporary project")
    parser.add_argument("--gpu", action="store_true",
                        help="the Mac's GPU through ANGLE on Metal (as Safari draws WebGL) instead of SwiftShader")
    parser.add_argument("sheets", nargs="*", type=Path)
    args = parser.parse_args()
    sheets = [p.resolve() for p in args.sheets] or samples()
    project = Path(tempfile.mkdtemp(prefix="palette-check-"))
    try:
        build(project, sheets)
        handler = functools.partial(QuietHandler, directory=str(project / "out"))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        runner = project / "runner.cjs"
        runner.write_text(RUNNER)
        url = f"http://127.0.0.1:{server.server_address[1]}/index.html"
        code = subprocess.run(["node", str(runner), args.modules, args.chrome, url,
                               "metal" if args.gpu else "swiftshader"]).returncode
        server.shutdown()
        return code
    finally:
        if args.keep:
            print("project kept in", project)
        else:
            shutil.rmtree(project, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
