#!/usr/bin/env python3
"""Render a .vox from N angles around it - the view the game gives.

    python tools/voxel/turntable.py <file.vox|dir> [out.png] [--views 8]

The review sheet shows two fixed projections, which is enough to judge a
cycle but not enough to judge a PROP held in a hand: a weapon can look
correct from the side and be rolled or skewed from anywhere else. Voxels
rotate for free in-engine, so every angle is a real angle a player will
see, and this renders them.

Painter's algorithm on rotated voxel coordinates - no smoothing, so what
comes out is the model, not a flattering render of it.
"""
import argparse
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_vox import read_vox                       # noqa: E402


def render(dims, vox, pal, ang, scale):
    cx, cy = (dims[0] - 1) / 2, (dims[1] - 1) / 2
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    pts = []
    for x, y, z, c in vox:
        dx, dy = x - cx, y - cy
        rx = dx * ca - dy * sa
        ry = dx * sa + dy * ca
        pts.append((ry, rx, z, pal[c - 1][:3] if pal and c >= 1
                    else (255, 0, 255)))
    span = max(dims[0], dims[1])
    w, h = int(span * scale), int(dims[2] * scale)
    im = Image.new("RGB", (w + scale, h + scale), (18, 18, 22))
    d = ImageDraw.Draw(im)
    pts.sort(key=lambda p: p[0])          # far first
    for depth, sx, sz, rgb in pts:
        px = (sx + span / 2) * scale
        py = (dims[2] - 1 - sz) * scale
        d.rectangle([px, py, px + scale - 1, py + scale - 1], fill=rgb)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out", nargs="?", default=None)
    ap.add_argument("--views", type=int, default=8)
    ap.add_argument("--scale", type=int, default=4)
    a = ap.parse_args()

    src = Path(a.src)
    if src.is_dir():
        files = sorted(src.glob("*.vox"))
        if not files:
            sys.exit(f"no .vox in {src}")
        src = files[0]
    dims, vox, pal = read_vox(src)
    ims = [render(dims, vox, pal, i * 360.0 / a.views, a.scale)
           for i in range(a.views)]
    w = sum(i.width for i in ims) + 6 * (len(ims) - 1)
    sheet = Image.new("RGB", (w, ims[0].height), (18, 18, 22))
    x = 0
    for i in ims:
        sheet.paste(i, (x, 0))
        x += i.width + 6
    out = Path(a.out) if a.out else src.with_name(src.stem + "_turntable.png")
    sheet.save(out)
    print(f"{src.name}: {a.views} views -> {out}")


if __name__ == "__main__":
    main()
