#!/usr/bin/env python3
"""LATHE archetype: turn a single sprite into a solid of revolution.

The cheapest and highest-fidelity of the three archetypes, and the
reason it works is a property of the art rather than a trick: most of
Wolf3D's props (urns, barrels, lamps, pillars, wells, plants) are drawn
as if they were turned on a lathe already. Revolving the sprite around
its vertical axis therefore reproduces the object rather than
approximating it.

WHY THE FRONT VIEW COMES OUT PIXEL-EXACT
Colour is sampled by SIGNED horizontal offset, not by radius. A surface
voxel sitting `dx` to the right of the axis is painted with the sprite
pixel `dx` to the right of the axis, whatever its depth. Seen head-on
the front elevation is then the original sprite exactly - including its
shading, which radius-based colouring would average away and flatten.

Turning the model does the physically right thing rather than a smear:
viewed from the side, the visible surface at height offset `dy` is the
voxel at dx = +/-sqrt(r^2 - dy^2), so the sprite's own light-to-dark
profile wraps around the object and reads as a lit, round solid.

SHAPE symmetry is what decides whether a sprite belongs in this
archetype, so that is what `shape_asymmetry` measures - which pixels are
painted at all, mirrored about the axis. Colour asymmetry is expected on
every shaded sprite and says nothing about lathe suitability; measuring
it instead would flag all 56 props as failures.

Sprite rows map to voxel z directly: KVX z points DOWN, and the pivot
sits at z = zsiz (the base), which is what puts a prop's feet on the
floor. Verified against Cheello's models, where the pivot is centred in
x and y and at 1.0 of z on every standing object.

  python tools/voxel/lathe.py build/assets/sprites/S012A0.png out.kvx
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kvx import Kvx                                        # noqa: E402

EMPTY = 255         # our internal "air" marker inside the grid
GAP_TOL = 2         # blank rows tolerated inside one object before it
                    # is treated as two separate drawings on the canvas


def load_indexed(path):
    """Return (indices[y][x] or None for air, width, height).

    Sprites come out of the VSWAP extractor as mode-P PNGs carrying the
    game palette, so the colour data is already palette indices - there
    is no quantisation step anywhere in this pipeline and no chance of
    colour drift.
    """
    im = Image.open(path)
    if im.mode != "P":
        raise SystemExit(f"{path}: expected an indexed (mode P) sprite, "
                         f"got {im.mode}")
    transparent = im.info.get("transparency")
    if isinstance(transparent, bytes):
        transparent = {i for i, a in enumerate(transparent) if a == 0}
    elif transparent is None:
        transparent = set()
    else:
        transparent = {transparent}
    w, h = im.size
    px = im.load()
    rows = [[None if px[x, y] in transparent else px[x, y]
             for x in range(w)] for y in range(h)]
    return rows, w, h


def lathe(rows, w, h, axis=None):
    """Revolve `rows` about a vertical axis. Returns (grid, dims, report).

    grid is indexed grid[x][y][z] to match KvxMip.from_grid.
    """
    spans = []
    for y in range(h):
        xs = [x for x in range(w) if rows[y][x] is not None]
        spans.append((min(xs), max(xs)) if xs else None)
    solid_rows = [i for i, s in enumerate(spans) if s]
    if not solid_rows:
        raise SystemExit("sprite is entirely transparent")

    left = min(spans[i][0] for i in solid_rows)
    right = max(spans[i][1] for i in solid_rows)

    # The axis is the MEDIAN row midpoint, not the bounding box centre.
    # Most Wolf props are drawn with a floor shadow thrown to one side,
    # and that shadow drags a bbox-derived axis off the object: the urn's
    # body is exactly symmetric about x=33, but its shadow reaches x=60
    # and pulls the bbox centre to 42. Revolving about 42 would both
    # mis-centre the model and sweep the shadow into a skirt around the
    # base. A median ignores a handful of outlying rows by construction.
    mids = sorted((spans[i][0] + spans[i][1]) / 2.0 for i in solid_rows)
    if axis is None:
        axis = mids[len(mids) // 2]

    # Per row, keep only the extent that exists on BOTH sides of the
    # axis. A one-sided overhang is shadow (or an asymmetric flourish
    # this archetype cannot represent); either way it is discarded here
    # rather than revolved. `clipped` reports how much paint that cost.
    radii = {}
    clip_row = {}
    for i in solid_rows:
        lo, hi = spans[i]
        r = min(axis - lo, hi - axis)
        if r < 0.5:
            clip_row[i] = hi - lo + 1
            continue
        radii[i] = r
        clip_row[i] = max(0, int((hi - lo + 1) - (2 * r + 1)))
    clipped = sum(clip_row.values())
    if not radii:
        raise SystemExit("no row is symmetric about the axis; this sprite "
                         "is not a lathe candidate")

    # A Wolf sprite can hold TWO disjoint objects on one canvas: ceiling
    # fixtures are drawn with the pool of light they cast painted
    # separately down on the floor. Treated as one solid, the chandelier
    # became a 61x61x64 column - the floor glow revolved into a giant
    # disc - and, because its lowest paint reached the canvas bottom, it
    # was planted on the ground instead of hanging. So split the painted
    # rows into vertically contiguous runs and keep the one carrying the
    # most paint; the fixture wins, the glow is dropped, and the model's
    # true base is recovered. Objects drawn as one piece have a single
    # run and are unaffected.
    kept = sorted(radii)
    runs, cur = [], [kept[0]]
    for a, b in zip(kept, kept[1:]):
        (cur.append(b) if b - a <= GAP_TOL + 1
         else (runs.append(cur), cur := [b]))
    runs.append(cur)
    if len(runs) > 1:
        # Rank by VERTICAL EXTENT, not by area. What we are discarding is
        # always a drawing on the floor - wide and flat - while the thing
        # we want has height. Ranking by area picks the wrong half: the
        # ceiling light's pool of light is 61 wide by 5 tall (305 px) and
        # beats its own 17-wide, 11-tall fixture (190 px).
        weight = [(len(r), sum(2 * radii[y] + 1 for y in r)) for r in runs]
        best = weight.index(max(weight))
        clipped += int(sum(w[1] for i, w in enumerate(weight)
                           if i != best))
        for i, r in enumerate(runs):
            if i != best:
                for y in r:
                    del radii[y]
        kept = sorted(radii)
    top, bottom = kept[0], kept[-1]
    radius = max(radii.values())
    xsiz = ysiz = int(radius * 2) + 1
    zsiz = bottom - top + 1
    if max(xsiz, ysiz, zsiz) > 255:
        raise SystemExit(f"model would be {xsiz}x{ysiz}x{zsiz}; KVX caps "
                         f"each axis at 255")
    centre = (xsiz - 1) / 2.0

    # Does the SHAPE mirror about the axis? Painted-vs-air only: a lathe
    # is the wrong archetype when the silhouette is lopsided, not when
    # the lighting is. Comparing colours here would score every shaded
    # sprite as ~100% asymmetric and condemn the whole tier.
    diff = total = 0
    for y, r in radii.items():
        for d in range(1, int(r) + 1):
            xa, xb = int(round(axis + d)), int(round(axis - d))
            a = rows[y][xa] is not None if 0 <= xa < w else False
            b = rows[y][xb] is not None if 0 <= xb < w else False
            if not (a or b):
                continue
            total += 1
            if a != b:
                diff += 1
    asymmetry = diff / total if total else 0.0

    grid = [[[EMPTY] * zsiz for _ in range(ysiz)] for _ in range(xsiz)]
    for z in range(zsiz):
        y_src = top + z
        if y_src not in radii:
            continue
        row_r = radii[y_src]

        def sample(dx):
            """Sprite pixel dx (signed) from the axis, falling back to
            the mirrored side where this row has no paint there."""
            for sx in (axis + dx, axis - dx):
                xi = int(round(sx))
                if 0 <= xi < w and rows[y_src][xi] is not None:
                    return rows[y_src][xi]
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

    report = {
        "dims": [xsiz, ysiz, zsiz],
        "axis": round(axis, 2),
        "shape_asymmetry": round(asymmetry, 4),
        "source_bbox": [left, top, right, bottom],
        "clipped_px": clipped,
        "kept_bottom": bottom,
        # Clipping split by height. Wolf props are drawn with a floor
        # shadow thrown to one side, so paint discarded in the bottom
        # fifth is almost always that shadow - which we WANT gone, since
        # a 3D model has no business carrying a painted shadow. Paint
        # discarded higher up is real object detail the revolution could
        # not represent. Judging on the total would reject the urn (a
        # perfect lathe whose shadow is 12% of its pixels) and is the
        # metric to distrust.
        "clipped_base": sum(v for k, v in clip_row.items()
                            if k > bottom - max(1, zsiz * 0.2)),
        "clipped_body": sum(v for k, v in clip_row.items()
                            if k <= bottom - max(1, zsiz * 0.2)),
        "body_paint": sum(
            1 for y in range(top, int(bottom - max(1, zsiz * 0.2)) + 1)
            for c in rows[y] if c is not None),
    }
    return grid, (xsiz, ysiz, zsiz), report


def kvx_palette(pal):
    """Game palette (256 x 8-bit RGB) -> KVX's 6-bit VGA triples.

    Verified against real files: every byte in a shipped KVX palette is
    <= 63, so the high two bits are dropped, not scaled."""
    out = bytearray(768)
    for i, (r, g, b) in enumerate(pal[:256]):
        out[i * 3:i * 3 + 3] = bytes((r >> 2, g >> 2, b >> 2))
    return bytes(out)


def build(sprite_path, palette, axis=None, floor=False):
    rows, w, h = load_indexed(sprite_path)
    grid, (xs, ys, zs), report = lathe(rows, w, h, axis)
    # Pivot: centred in x/y. In z it must reproduce WHERE ON ITS CANVAS
    # the sprite drew the object, not merely stand the model on its own
    # base. The model is cropped to the painted rows, so a chandelier -
    # drawn in the top half of a 64px canvas with nothing beneath it -
    # would otherwise be planted on the floor instead of hanging from
    # the ceiling. Dropping the pivot by the number of blank canvas rows
    # below the object restores the sprite's exact height, and does so
    # for every class of prop at once: standing objects reach the canvas
    # bottom, so their offset is zero and nothing changes.
    below = (h - 1) - report["kept_bottom"]
    pivot = (xs * 128, ys * 128, (zs + below) * 256)
    report["hangs_by"] = below
    k = Kvx.from_grid(grid, xs, ys, zs, kvx_palette(palette),
                      pivot=pivot, empty=EMPTY)
    report["slabs"] = k.mips[0].slab_count()
    report["voxels"] = k.mips[0].voxel_count()
    return k, report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sprite")
    ap.add_argument("out")
    ap.add_argument("--palette", default="build/vswap/palette.json")
    ap.add_argument("--axis", type=float, default=None,
                    help="override the axis of revolution (sprite x)")
    ap.add_argument("--floor", action="store_true",
                    help="pivot at mid-height, for floor-flat items")
    a = ap.parse_args()
    pal = json.loads(Path(a.palette).read_text())
    k, report = build(a.sprite, pal, a.axis, a.floor)
    Path(a.out).write_bytes(k.to_bytes())
    print(f"{a.out}: {report}")


if __name__ == "__main__":
    main()
