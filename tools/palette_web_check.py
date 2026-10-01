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

Without sheets it takes the two smallest, a median and a larger sheet of each
folder in palette_sheet.gd's KINDS. See docs/technical/palette-textures.md.
"""
import argparse
import json
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
  await page.addInitScript(() => {
    // Observe real WebGL allocation/release calls, rather than report a
    // width×height estimate as physical GPU residency. Unknown formats fail.
    const glp = WebGL2RenderingContext.prototype;
    const sizes = new Map(), bound = new Map();
    const nativeBind = glp.bindTexture;
    glp.bindTexture = function(target, texture) { bound.set(target, texture); return nativeBind.apply(this, arguments); };
    const bpp = new Map([[0x8229,1],[0x822B,2],[0x8051,3],[0x8058,4],[0x1903,1],[0x1907,3],[0x1908,4],[0x881A,8],[0x8814,16],[0x822D,2],[0x822E,4],[0x8D7C,4],[0x81A5,2],[0x8059,4],[0x88F0,4]]);
    const unknown = [];
    const note = (target, level, format, width, height) => {
      const texture = bound.get(target); if (!texture) return;
      if (!bpp.has(format)) { unknown.push(format); return; }
      if (!sizes.has(texture)) sizes.set(texture,new Map());
      sizes.get(texture).set(level,width*height*bpp.get(format));
    };
    const image = glp.texImage2D;
    glp.texImage2D = function(...a) {
      const result = image.apply(this,a);
      if (a.length >= 9) note(a[0],a[1],a[2],a[3],a[4]);
      else note(a[0],a[1],a[2],a[5].width,a[5].height);
      return result;
    };
    const storage = glp.texStorage2D;
    glp.texStorage2D = function(target, levels, format, width, height) {
      const result = storage.apply(this,arguments);
      for(let level=0;level<levels;level++) note(target,level,format,Math.max(1,width>>level),Math.max(1,height>>level));
      return result;
    };
    const remove = glp.deleteTexture;
    glp.deleteTexture = function(texture) { sizes.delete(texture); return remove.apply(this,arguments); };
    window.__paletteAllocations = () => ({bytes:[...sizes.values()].reduce((sum,levels)=>sum+[...levels.values()].reduce((a,b)=>a+b,0),0),textures:sizes.size,unknown});
  });
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
        picks = sheets[:2] + [sheets[len(sheets) * q // 4] for q in (2, 3) if len(sheets) > 3]
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


def build(project, sheets, thumbs=False):
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
    if thumbs:
        build_thumbnails(project)
    (project / "out").mkdir()
    subprocess.run([godot(), "--headless", "--path", str(project), "--import"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = subprocess.run([godot(), "--headless", "--path", str(project), "--export-debug", "Web",
                             str(project / "out/index.html")], capture_output=True, text=True)
    if not (project / "out/index.html").exists():
        sys.exit("export failed:\n" + result.stdout[-2000:] + result.stderr[-2000:])


def build_thumbnails(project):
    """Independent nearest references from original frames; never Lanczos.

    Both variants are included here for measurement. Production packs remain
    separate, selected by PetThumbnails.atlas_paths().
    """
    from PIL import Image
    import build_pet_thumbs as thumbs
    index = json.loads((LEGACY/'thumbs/index.json').read_text())
    output = project/'thumbs'
    output.mkdir()
    shutil.copy(CLIENT/'tests/perf/pet_thumbnail_render_check.gd',project/'tests/perf/')
    (project/'check.tscn').write_text(SCENE.replace('palette_render_check.gd','pet_thumbnail_render_check.gd'))
    references = []
    for name in index['palette_files']:
        with Image.open(LEGACY/'thumbs'/name) as atlas:
            references.append(Image.new('RGBA',atlas.size))
    cache = {}
    entries = thumbs.entries(LEGACY/'battle')
    for sprite, (number,x,y,w,h) in index['sprites'].items():
        animations,sheets = entries[sprite]
        crop = thumbs.picture(LEGACY/'battle',sheets,thumbs.standing_frame(animations),cache,Image.Resampling.NEAREST)
        references[number].paste(crop,(x,y))
    for i,(nearest,rgba) in enumerate(zip(index['palette_files'],index['files'])):
        shutil.copy(LEGACY/'thumbs'/nearest,output/f'palette-{i}.sheet')
        shutil.copy(LEGACY/'thumbs'/rgba,output/f'rgba-{i}.png')
        # An independent original-Lanczos import with the same default importer
        # flags as production. Linear sampling must match that baseline.
        shutil.copy(LEGACY/'thumbs'/rgba,output/f'baseline-{i}.png')
        references[i].save(output/f'nearest-{i}.sheet',format='PNG')
    (output/'index.json').write_text(json.dumps(index))
    preset = (project/'export_presets.cfg').read_text().replace('include_filter="sheets/*"','include_filter="sheets/*,thumbs/*"')
    (project/'export_presets.cfg').write_text(preset)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--modules", required=True, help="folder playwright-core was installed into")
    parser.add_argument("--chrome", required=True, help="Chromium executable")
    parser.add_argument("--thumbs", action="store_true", help="all thumbnail atlases, independent nearest references, linear RGBA baseline and instrumented allocations")
    parser.add_argument("--keep", action="store_true", help="keep the temporary project")
    parser.add_argument("--gpu", action="store_true",
                        help="the Mac's GPU through ANGLE on Metal (as Safari draws WebGL) instead of SwiftShader")
    parser.add_argument("sheets", nargs="*", type=Path)
    args = parser.parse_args()
    sheets = [] if args.thumbs else ([p.resolve() for p in args.sheets] or samples())
    project = Path(tempfile.mkdtemp(prefix="palette-check-"))
    try:
        build(project, sheets, args.thumbs)
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
