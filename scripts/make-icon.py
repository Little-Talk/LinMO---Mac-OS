#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Resources/AppIcon/AppIcon.svg"
MASTER = ROOT / "Resources/AppIcon/AppIcon.png"
ICNS = ROOT / "Resources/AppIcon.icns"
ICONSET = ROOT / "Resources/AppIcon.xcassets/AppIcon.appiconset"

SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def render_master():
    if shutil.which("rsvg-convert"):
        subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", "-o", str(MASTER), str(SRC)], check=True)
        return
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        if shutil.which("node"):
            render_with_node()
            return
        sys.exit("ต้องมี rsvg-convert หรือ Playwright (Python หรือ Node) เพื่อแปลง SVG")
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1024, "height": 1024})
        page.set_content(f'<html><body style="margin:0;background:transparent">{SRC.read_text()}</body></html>')
        page.locator("svg").screenshot(path=str(MASTER), omit_background=True)
        browser.close()


def render_with_node():
    script = f"""
const {{ chromium }} = require('playwright');
(async () => {{
  const browser = await chromium.launch();
  const page = await browser.newPage({{ viewport: {{ width: 1024, height: 1024 }} }});
  await page.setContent('<html><body style="margin:0;background:transparent">' + {json.dumps(SRC.read_text())} + '</body></html>');
  await page.locator('svg').screenshot({{ path: {json.dumps(str(MASTER))}, omitBackground: true }});
  await browser.close();
}})().catch(e => {{ console.error(e); process.exit(1); }});
"""
    subprocess.run(["node", "-e", script], check=True)


def main():
    render_master()
    master = Image.open(MASTER).convert("RGBA")
    assert master.size == (1024, 1024), master.size

    ICONSET.mkdir(parents=True, exist_ok=True)
    images = []
    for points, scale in SIZES:
        px = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        img = master.resize((px, px), Image.LANCZOS)
        img.save(ICONSET / name, optimize=True)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    (ICONSET / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (ICONSET.parent / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

    if shutil.which("iconutil"):
        tmp = ROOT / "build/AppIcon.iconset"
        shutil.rmtree(tmp, ignore_errors=True)
        shutil.copytree(ICONSET, tmp, ignore=shutil.ignore_patterns("Contents.json"))
        subprocess.run(["iconutil", "-c", "icns", "-o", str(ICNS), str(tmp)], check=True)
    else:
        extra = [master.resize((s, s), Image.LANCZOS) for s in (16, 32, 64, 128, 256, 512)]
        master.save(ICNS, format="ICNS", append_images=extra)
    print(f"✅ {MASTER.relative_to(ROOT)}, {ICNS.relative_to(ROOT)}, {ICONSET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
