#!/usr/bin/env python3
"""TRUE-REVOLVE archetype v2: lathe with top-face reprojection.

The plain lathe treated the sprite as a side elevation. Wolf props are
actually drawn from slightly ABOVE (the well's rim ellipse: back edge
row 39, full width by row 43 - semi-minor 4 over radius 21, an ~11 deg
downward view). Every pixel in that rim band is part of a HORIZONTAL
surface, and revolving it as if it were profile is what domed the
barrels and turned the well's water into a blue stripe around the
circumference (user repro, gallery session 2026-07-30).

THE INVERSION
For a cylinder of radius R viewed at angle theta, the top face projects
to an ellipse with semi-minor b = R*sin(theta), centred b rows below
its back edge. A pixel (dx, dy) inside that ellipse (dy measured from
the ellipse centre) sits on the disc at world position

    (dx, dy * R/b)          -- depth recovered by dividing out sin(theta)

so the whole band flattens onto ONE voxel layer at the model's top:
the water becomes a flat blue disc lying in the well, the barrel top
becomes a lid. Wall pixels (below the ellipse's lower edge at their x)
revolve exactly as before; at these angles the wall's vertical
foreshortening is cos(theta) > 0.98, less than a voxel, and is ignored.

The model's true height is the sprite height minus the 2b rows the
ellipse occupied - the drum was always drawn taller than the object.

  python tools/voxel/lathe_top.py build/assets/sprites/S036A0.png out.kvx
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kvx import Kvx                                        # noqa: E402
from lathe import EMPTY, kvx_palette, load_indexed         # noqa: E402


def analyse(rows, w, h):
    """Row spans, axis, and the top-face ellipse (t0, b, R)."""
    spans = {}
    for y in range(h):
        xs = [x for x in range(w) if rows[y][x] is not None]
        if xs:
            spans[y] = (min(xs), max(xs))
    if not spans:
        raise SystemExit("sprite is empty")
    ys = sorted(spans)

    mids = sorted((lo + hi) / 2.0 for lo, hi in spans.values())
    axis = mids[len(mids) // 2]

    # Clip to symmetric extent (the painted shadow problem, as before).
    radii = {y: min(axis - lo, hi - axis) for y, (lo, hi) in spans.items()
             if min(axis - lo, hi - axis) >= 0.5}
    ys = sorted(radii)
    t0 = ys[0]
    R = max(radii.values())

    # The ellipse's semi-minor axis: rows from the top of the object to
    # the first row that reaches (nearly) full width. "Nearly" absorbs
    # one ragged pixel on hand-drawn art.
    b = 0
    for y in ys:
        if radii[y] >= R - 1:
            b = y - t0
            break
    return spans, radii, axis, t0, b, R, ys


def build(sprite_path, palette):
    rows, w, h = load_indexed(sprite_path)
    spans, radii, axis, t0, b, R, ys = analyse(rows, w, h)
    bottom = ys[-1]
    if b < 2:
        raise SystemExit(f"no top ellipse detected (b={b}); use the "
                         f"plain lathe for this sprite")

    ec = t0 + b                     # ellipse centre row
    xsiz = ysiz = int(R * 2) + 1
    zsiz = bottom - (t0 + 2 * b) + 1 + 1   # wall rows + one lid layer
    centre = (xsiz - 1) / 2.0

    grid = [[[EMPTY] * zsiz for _ in range(ysiz)] for _ in range(xsiz)]

    # --- the lid ------------------------------------------------------
    # Inverse mapping: iterate DISC voxels and sample the sprite, not
    # the other way round. Scattering the ellipse's 2b+1 source rows
    # onto 2R+1 disc rows leaves stripes of air between them (first
    # attempt rendered exactly that); sampling source-from-dest fills
    # every disc voxel by construction.
    lid = 0
    for gx in range(xsiz):
        dx = gx - centre
        for gy in range(ysiz):
            gv = gy - centre                  # world depth from axis
            if dx * dx + gv * gv > R * R:
                continue
            y = int(round(ec + gv * b / R))   # compress depth back to screen
            x = int(round(axis + dx))
            if 0 <= y < h and 0 <= x < w and rows[y][x] is not None:
                grid[gx][gy][0] = rows[y][x]
                lid += 1

    # --- the wall: profile rows below the ellipse, revolved ----------
    for y in range(t0 + 2 * b + 1, bottom + 1):
        if y not in radii:
            continue
        z = y - (t0 + 2 * b)
        row_r = radii[y]

        def sample(dx, _y=y):
            for sx in (axis + dx, axis - dx):
                xi = int(round(sx))
                if 0 <= xi < w and rows[_y][xi] is not None:
                    return rows[_y][xi]
            return None

        for gx in range(xsiz):
            dx = gx - centre
            c = sample(dx)
            if c is None:
                continue
            for gy in range(ysiz):
                dy = gy - centre
                if (dx * dx + dy * dy) ** 0.5 > row_r + 0.5:
                    continue
                grid[gx][gy][z] = c

    below = (h - 1) - bottom
    pivot = (xsiz * 128, ysiz * 128, (zsiz + below) * 256)
    k = Kvx.from_grid(grid, xsiz, ysiz, zsiz, kvx_palette(palette),
                      pivot=pivot, empty=EMPTY)
    theta = __import__("math").degrees(__import__("math").asin(b / R))
    report = {"dims": [xsiz, ysiz, zsiz], "axis": round(axis, 2),
              "ellipse_b": b, "R": int(R),
              "view_angle_deg": round(theta, 1), "lid_px": lid,
              "slabs": k.mips[0].slab_count(),
              "voxels": k.mips[0].voxel_count()}
    return k, report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sprite")
    ap.add_argument("out")
    ap.add_argument("--palette", default="build/vswap/palette.json")
    a = ap.parse_args()
    pal = json.loads(Path(a.palette).read_text())
    k, report = build(a.sprite, pal)
    Path(a.out).write_bytes(k.to_bytes())
    print(f"{a.out}: {report}")


if __name__ == "__main__":
    main()
