#!/usr/bin/env python3
"""HULL archetype: space-carve an enemy frame from its 8 rotation views.

Enemies are the one class of Wolf sprite that comes with real 3D
evidence: eight views at 45-degree steps. The visual hull follows
mechanically - start from a solid block and carve away every voxel that
projects outside ANY view's silhouette. What survives matches all eight
silhouettes by construction. No AI, no invention; every voxel is
testified to by the art.

CARVING
Views are orthographic (Wolf scales sprites uniformly with distance -
there is no perspective inside a sprite). Viewer azimuth for rotation r
is (r-1)*45deg; a voxel at horizontal offset (dx, dy) from the axis
projects to screen column  u = dx*cos(phi) + dy*sin(phi)  and keeps its
row. Silhouettes are dilated by one pixel first: hand-drawn rotations
disagree by a pixel here and there, and the strict intersection eats
thin limbs (rifle barrels, ankles).

COLOUR
Each view claims the voxels it can actually see (first solid voxel
along its rays). A voxel seen by several views takes the one that faces
it most squarely - the dot product of the view ray with the voxel's
exposed-face normal - with the FRONT view winning ties, since front is
what players see most. Voxels no view reaches (armpits, top of the
head) inherit the nearest stamped colour by BFS, which reads as the
local material continuing around the corner.

LIMIT (honest): concavities no silhouette can testify to - the hollow
of the back between the shoulder blades - stay filled at hull level.
That is the known gap between carving and Cheello's hand-sculpts.

  python tools/voxel/hull.py GRDSA out.kvx     # GRDSA1..GRDSA8
"""
import argparse
import json
import math
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kvx import Kvx                                        # noqa: E402
from lathe import EMPTY, kvx_palette, load_indexed         # noqa: E402

SPRITES = Path(__file__).resolve().parent.parent.parent / \
    "build" / "assets" / "sprites"
AXIS = 31.5                 # Wolf sprites are drawn on a centred canvas
DILATE = 1                  # px of slack per silhouette


def load_views(stem, directory=SPRITES):
    """rows[r][y][x] for rotations 1..8, plus canvas size."""
    views = {}
    w = h = None
    for r in range(1, 9):
        p = directory / f"{stem}{r}.png"
        if not p.exists():
            raise SystemExit(f"missing rotation: {p}")
        rows, w, h = load_indexed(p)
        views[r] = rows
    return views, w, h


def dilate(mask):
    """Grow a boolean mask by one pixel in the four directions."""
    h, w = len(mask), len(mask[0])
    out = [row[:] for row in mask]
    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                continue
            if ((x > 0 and mask[y][x - 1]) or
                    (x + 1 < w and mask[y][x + 1]) or
                    (y > 0 and mask[y - 1][x]) or
                    (y + 1 < h and mask[y + 1][x])):
                out[y][x] = True
    return out


def build(stem, palette, directory=SPRITES):
    views, w, h = load_views(stem, directory)

    paint_rows = [y for y in range(h)
                  if any(views[r][y][x] is not None
                         for r in views for x in range(w))]
    top, bottom = paint_rows[0], paint_rows[-1]
    zsiz = bottom - top + 1

    # Horizontal extent: the widest half-width over all views, so the
    # block is guaranteed to contain the hull.
    half = 1
    for r in views:
        for y in paint_rows:
            for x in range(w):
                if views[r][y][x] is not None:
                    half = max(half, abs(x - AXIS))
    n = int(half) * 2 + 3
    centre = (n - 1) / 2.0
    xsiz = ysiz = n

    sil = {}
    for r in views:
        m = [[views[r][y][x] is not None for x in range(w)]
             for y in range(h)]
        for _ in range(DILATE):
            m = dilate(m)
        sil[r] = m

    phis = {r: math.radians((r - 1) * 45.0) for r in range(1, 9)}
    cs = {r: (math.cos(p), math.sin(p)) for r, p in phis.items()}

    # --- carve --------------------------------------------------------
    solid = [[[True] * zsiz for _ in range(ysiz)] for _ in range(xsiz)]
    kept = 0
    for gx in range(xsiz):
        dx = gx - centre
        for gy in range(ysiz):
            dy = gy - centre
            cols = {}
            ok_all = True
            for r in range(1, 9):
                c, s = cs[r]
                u = int(round(AXIS + dx * c + dy * s))
                if not (0 <= u < w):
                    ok_all = False
                    break
                cols[r] = u
            for z in range(zsiz):
                if not ok_all:
                    solid[gx][gy][z] = False
                    continue
                y = top + z
                if all(sil[r][y][cols[r]] for r in range(1, 9)):
                    kept += 1
                else:
                    solid[gx][gy][z] = False

    # --- colour stamp -------------------------------------------------
    # First-hit voxels per view; squarest view wins. Ray direction for
    # view r points INTO the scene: (-cos, -sin) in (dx, dy).
    grid = [[[EMPTY] * zsiz for _ in range(ysiz)] for _ in range(xsiz)]
    best = {}
    order = (1, 5, 3, 7, 2, 4, 6, 8)          # front, back, sides, diagonals
    for r in order:
        c, s = cs[r]
        rows = views[r]
        # sweep rays: for each (u, z) march from the viewer inward
        for u in range(w):
            col_px = None
            for z in range(zsiz):
                y = top + z
                px = rows[y][u]
                if px is None:
                    continue
                # march: parametrise points with projection u
                hitv = _first_hit(solid, xsiz, ysiz, centre, AXIS,
                                  u, c, s, z)
                if hitv is None:
                    continue
                gx, gy = hitv
                # squareness: exposed-face normal vs incoming ray
                nx = ((gx + 1 >= xsiz or not solid[gx + 1][gy][z]) -
                      (gx - 1 < 0 or not solid[gx - 1][gy][z]))
                ny = ((gy + 1 >= ysiz or not solid[gx][gy + 1][z]) -
                      (gy - 1 < 0 or not solid[gx][gy - 1][z]))
                dot = nx * c + ny * s
                score = dot
                key = (gx, gy, z)
                if key not in best or score > best[key][0] + 1e-9:
                    best[key] = (score, px)
    for (gx, gy, z), (_s, px) in best.items():
        grid[gx][gy][z] = px

    # --- fill unseen surface voxels from neighbours -------------------
    q = deque((gx, gy, z) for gx in range(xsiz) for gy in range(ysiz)
              for z in range(zsiz)
              if solid[gx][gy][z] and grid[gx][gy][z] != EMPTY)
    seen = set(q)
    filled = 0
    while q:
        gx, gy, z = q.popleft()
        col = grid[gx][gy][z]
        for ax, ay, az in ((gx + 1, gy, z), (gx - 1, gy, z),
                           (gx, gy + 1, z), (gx, gy - 1, z),
                           (gx, gy, z + 1), (gx, gy, z - 1)):
            if not (0 <= ax < xsiz and 0 <= ay < ysiz and 0 <= az < zsiz):
                continue
            if not solid[ax][ay][az] or (ax, ay, az) in seen:
                continue
            grid[ax][ay][az] = col
            seen.add((ax, ay, az))
            filled += 1
            q.append((ax, ay, az))

    for gx in range(xsiz):
        for gy in range(ysiz):
            for z in range(zsiz):
                if not solid[gx][gy][z]:
                    grid[gx][gy][z] = EMPTY

    below = (h - 1) - bottom
    pivot = (xsiz * 128, ysiz * 128, (zsiz + below) * 256)
    k = Kvx.from_grid(grid, xsiz, ysiz, zsiz, kvx_palette(palette),
                      pivot=pivot, empty=EMPTY)
    report = {"dims": [xsiz, ysiz, zsiz], "carved_kept": kept,
              "stamped": len(best), "bfs_filled": filled,
              "slabs": k.mips[0].slab_count(),
              "voxels": k.mips[0].voxel_count()}
    return k, report


def _first_hit(solid, xsiz, ysiz, centre, axis, u, c, s, z):
    """First solid voxel along the ray of view (c,s) that projects to
    screen column u, marching from the viewer's side inward."""
    # Points (dx, dy) with dx*c + dy*s == u - AXIS form a line; walk it
    # by the perpendicular parameter t from the viewer (t large +) in.
    du = u - axis
    n = xsiz
    hits = []
    for t in range(-n, n + 1):
        dx = du * c - t * s
        dy = du * s + t * c
        gx = int(round(centre + dx))
        gy = int(round(centre + dy))
        if 0 <= gx < xsiz and 0 <= gy < ysiz and solid[gx][gy][z]:
            hits.append((t, gx, gy))
    if not hits:
        return None
    # viewer sits at positive t along (c, s): nearest = max t
    t, gx, gy = max(hits)
    return gx, gy


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("stem", help="sprite stem, e.g. GRDSA for GRDSA1..8")
    ap.add_argument("out")
    ap.add_argument("--palette", default="build/vswap/palette.json")
    a = ap.parse_args()
    pal = json.loads(Path(a.palette).read_text())
    k, report = build(a.stem, pal)
    Path(a.out).write_bytes(k.to_bytes())
    print(f"{a.out}: {report}")


if __name__ == "__main__":
    main()
