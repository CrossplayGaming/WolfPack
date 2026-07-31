#!/usr/bin/env python3
"""Generative-recovery route: AI-reconstructed mesh -> game-true KVX.

Eric's pipeline for sprites whose depth the art never shows (the hull
experiment proved 8 silhouettes alone are not enough for organic
shapes): sprite -> pristine multi-angle turnaround (ChatGPT) -> Meshy
multi-image-to-3D -> GLB into import/ -> THIS TOOL -> gallery verdict.

The division of authority, per the charter's synthesis: the AI proposes
the FLESH, the sprites impose the SKELETON and the SKIN.

  1. VOXELIZE   the mesh at the sprite's own paint height, through the
                proven CCFPS voxelizer (barycentric rasterisation).
  2. ORIENT     measured, not assumed: try all four yaw quarter-turns
                and keep the one whose front silhouette best matches
                the sprite's front view (IoU). Meshy's forward axis is
                not reliable; measurement is.
  3. CARVE      delete every voxel that falls outside any of the 8
                rotation silhouettes (dilated 1px). AI excess is
                removed mechanically; deficits are only reported -
                nothing is ever auto-filled.
  4. STAMP      surfaces visible from the 8 canonical angles take the
                sprite's exact palette pixels. The AI's own texture
                survives only on surfaces no sprite ever saw, quantised
                to the game palette (nearest RGB).
  5. KVX        pivot centred, base at the feet.

  python tools/voxel/meshy.py import/guard.glb GRDSA out.kvx
  python tools/voxel/meshy.py import/guard.glb GRDSA out.kvx --no-stamp
"""
import argparse
import json
import math
import subprocess
import sys
import tempfile
from collections import deque
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

from kvx import Kvx                                        # noqa: E402
from lathe import EMPTY, kvx_palette                       # noqa: E402
import hull as hull_mod                                    # noqa: E402

BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.2"
               r"\blender.exe")
CCFPS_VOX = Path(r"F:\CrystalCavesFPS\tools\voxel")


def glb_to_obj(glb, workdir):
    """Headless-Blender bridge (proven in CCFPS). Returns the OBJ path."""
    if not BLENDER.exists():
        raise SystemExit(f"Blender not found at {BLENDER}")
    script = CCFPS_VOX / "glb_to_obj.py"
    r = subprocess.run([str(BLENDER), "--background", "--python",
                        str(script), "--", str(glb), str(workdir)],
                       capture_output=True, text=True, timeout=300)
    obj = workdir / (Path(glb).stem + ".obj")
    if not obj.exists():
        sys.exit(f"Blender export failed:\n{r.stdout[-800:]}"
                 f"\n{r.stderr[-800:]}")
    return obj


def voxelize_obj(obj, height):
    """Run the CCFPS voxelizer in-process. Returns ({(x,y,z): rgb}, dims)."""
    sys.path.insert(0, str(CCFPS_VOX))
    import voxelize as vx
    verts, uvs, faces = vx.parse_obj(obj)
    return vx.voxelize(verts, uvs, faces, height)


def fill_interior(solid, dims):
    """The voxelizer keeps only the mesh SHELL; carving needs a solid
    volume or silhouette tests punch through to the far wall. Flood-fill
    air from outside; anything unreached is interior - make it solid
    (colour borrowed from the nearest shell voxel later; EMPTY marks it
    unstamped for now)."""
    nx, ny, nz = dims
    outside = set()
    q = deque()
    for x in (-1, nx):
        for y in range(-1, ny + 1):
            for z in range(-1, nz + 1):
                q.append((x, y, z))
    for y in (-1, ny):
        for x in range(nx):
            for z in range(-1, nz + 1):
                q.append((x, y, z))
    for z in (-1, nz):
        for x in range(nx):
            for y in range(ny):
                q.append((x, y, z))
    q = deque(set(q))
    outside.update(q)
    while q:
        x, y, z = q.popleft()
        for a, b, c in ((x+1,y,z),(x-1,y,z),(x,y+1,z),(x,y-1,z),
                        (x,y,z+1),(x,y,z-1)):
            if not (-1 <= a <= nx and -1 <= b <= ny and -1 <= c <= nz):
                continue
            if (a, b, c) in outside or (a, b, c) in solid:
                continue
            if 0 <= a < nx and 0 <= b < ny and 0 <= c < nz:
                outside.add((a, b, c))
                q.append((a, b, c))
            else:
                outside.add((a, b, c))
                q.append((a, b, c))
    added = 0
    for x in range(nx):
        for y in range(ny):
            for z in range(nz):
                if (x, y, z) not in solid and (x, y, z) not in outside:
                    solid[(x, y, z)] = None      # interior, uncoloured
                    added += 1
    return added


def sil_iou(mask_a, mask_b):
    inter = sum(1 for k in mask_a if k in mask_b)
    union = len(mask_a | mask_b)
    return inter / union if union else 0.0


def orient(solid, dims, views, top, zsiz, w):
    """Pick the yaw quarter-turn whose front projection best matches the
    sprite's front silhouette. Returns (rotated solid, dims, iou, k)."""
    nx, ny, nz = dims
    # sprite front silhouette in (u, z) space, centred
    spr = set()
    for z in range(zsiz):
        y = top + z
        for x in range(w):
            if views[1][y][x] is not None:
                spr.add((round(x - hull_mod.AXIS), z))

    best = None
    for k in range(4):
        if k == 0:
            rot = solid
            rd = (nx, ny, nz)
        else:
            rot = {}
            for (x, y, z), c in solid.items():
                if k == 1:
                    x, y = y, nx - 1 - x
                elif k == 2:
                    x, y = nx - 1 - x, ny - 1 - y
                else:
                    x, y = ny - 1 - y, x
                rot[(x, y, z)] = c
            rd = (ny, nx, nz) if k % 2 else (nx, ny, nz)
        cx = (rd[0] - 1) / 2.0
        # front view = looking along +y: project (x, z), voxel z is
        # mesh-up so screen row = zsiz-1-z
        proj = {(round(x - cx), rd[2] - 1 - z)
                for (x, y, z) in rot}
        iou = sil_iou(proj, spr)
        if best is None or iou > best[2]:
            best = (rot, rd, iou, k)
    return best


def build(glb, stem, palette, stamp=True):
    views, w, h = hull_mod.load_views(stem)
    paint_rows = [y for y in range(h)
                  if any(views[r][y][x] is not None
                         for r in views for x in range(w))]
    top, bottom = paint_rows[0], paint_rows[-1]
    zsiz = bottom - top + 1

    with tempfile.TemporaryDirectory() as td:
        obj = glb_to_obj(glb, Path(td))
        shell, dims = voxelize_obj(obj, zsiz)
    interior = fill_interior(shell, dims)
    shell, dims, iou, k = orient(shell, dims, views, top, zsiz, w)
    print(f"  mesh: {len(shell)} voxels {dims}, interior filled "
          f"{interior}, yaw {k * 90} deg (front IoU {iou:.2f})")

    # centre the model on the sprite axis; grid indexed [gx][gy][gz]
    # with KVX z pointing DOWN (screen row order)
    nx, ny, nz = dims
    half = max(nx, ny)
    n = half + 2
    centre = (n - 1) / 2.0
    ox = centre - (nx - 1) / 2.0
    oy = centre - (ny - 1) / 2.0

    sil = {}
    for r in views:
        m = [[views[r][y][x] is not None for x in range(w)]
             for y in range(h)]
        m = hull_mod.dilate(m)
        sil[r] = m
    cs = {r: (math.cos(math.radians((r - 1) * 45.0)),
              math.sin(math.radians((r - 1) * 45.0))) for r in range(1, 9)}

    solid = [[[False] * zsiz for _ in range(n)] for _ in range(n)]
    colour = {}
    carved = kept = 0
    for (x, y, z), c in shell.items():
        gx = int(round(x + ox))
        gy = int(round(y + oy))
        gz = zsiz - 1 - z                     # mesh up -> KVX down
        if not (0 <= gx < n and 0 <= gy < n and 0 <= gz < zsiz):
            continue
        dx, dy = gx - centre, gy - centre
        ok = True
        for r in range(1, 9):
            cc, ss = cs[r]
            u = int(round(hull_mod.AXIS + dx * cc + dy * ss))
            yy = top + gz
            if not (0 <= u < w) or not sil[r][yy][u]:
                ok = False
                break
        if ok:
            solid[gx][gy][gz] = True
            if c is not None:
                colour[(gx, gy, gz)] = c
            kept += 1
        else:
            carved += 1
    print(f"  carve: kept {kept}, removed {carved} "
          f"({carved * 100 // max(1, kept + carved)}% of mesh)")

    grid = [[[EMPTY] * zsiz for _ in range(n)] for _ in range(n)]

    # nearest-palette for the AI texture on never-seen surfaces
    def quant(rgb):
        return min(range(256),
                   key=lambda i: sum((a - b) ** 2
                                     for a, b in zip(palette[i], rgb)))
    qcache = {}
    for key, c in colour.items():
        if c not in qcache:
            qcache[c] = quant(c)
        grid[key[0]][key[1]][key[2]] = qcache[c]

    stamped = 0
    if stamp:
        best = {}
        for r in (1, 5, 3, 7, 2, 4, 6, 8):
            cc, ss = cs[r]
            rows = views[r]
            for u in range(w):
                for gz in range(zsiz):
                    px = rows[top + gz][u]
                    if px is None:
                        continue
                    hit = hull_mod._first_hit(solid, n, n, centre,
                                              hull_mod.AXIS, u, cc, ss, gz)
                    if hit is None:
                        continue
                    gx, gy = hit
                    nxn = ((gx + 1 >= n or not solid[gx + 1][gy][gz]) -
                           (gx - 1 < 0 or not solid[gx - 1][gy][gz]))
                    nyn = ((gy + 1 >= n or not solid[gx][gy + 1][gz]) -
                           (gy - 1 < 0 or not solid[gx][gy - 1][gz]))
                    dot = nxn * cc + nyn * ss
                    key = (gx, gy, gz)
                    if key not in best or dot > best[key][0] + 1e-9:
                        best[key] = (dot, px)
        for (gx, gy, gz), (_d, px) in best.items():
            grid[gx][gy][gz] = px
        stamped = len(best)

    # BFS-fill any solid voxel still uncoloured (interior, crevices)
    q = deque(k_ for k_ in
              ((x, y, z) for x in range(n) for y in range(n)
               for z in range(zsiz))
              if solid[k_[0]][k_[1]][k_[2]] and
              grid[k_[0]][k_[1]][k_[2]] != EMPTY)
    seen = set(q)
    while q:
        gx, gy, gz = q.popleft()
        col = grid[gx][gy][gz]
        for a, b, c_ in ((gx+1,gy,gz),(gx-1,gy,gz),(gx,gy+1,gz),
                         (gx,gy-1,gz),(gx,gy,gz+1),(gx,gy,gz-1)):
            if not (0 <= a < n and 0 <= b < n and 0 <= c_ < zsiz):
                continue
            if not solid[a][b][c_] or (a, b, c_) in seen:
                continue
            grid[a][b][c_] = col
            seen.add((a, b, c_))
            q.append((a, b, c_))

    for gx in range(n):
        for gy in range(n):
            for gz in range(zsiz):
                if not solid[gx][gy][gz]:
                    grid[gx][gy][gz] = EMPTY

    below = (h - 1) - bottom
    pivot = (n * 128, n * 128, (zsiz + below) * 256)
    kv = Kvx.from_grid(grid, n, n, zsiz, kvx_palette(palette),
                       pivot=pivot, empty=EMPTY)
    report = {"dims": [n, n, zsiz], "mesh_voxels": len(shell),
              "carved_away": carved, "front_iou": round(iou, 3),
              "stamped": stamped,
              "voxels": kv.mips[0].voxel_count()}
    return kv, report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("glb")
    ap.add_argument("stem", help="rotation sprite stem, e.g. GRDSA")
    ap.add_argument("out")
    ap.add_argument("--no-stamp", action="store_true",
                    help="keep the AI texture everywhere (comparison)")
    ap.add_argument("--palette", default="build/vswap/palette.json")
    a = ap.parse_args()
    pal = json.loads((ROOT / a.palette).read_text())
    kv, rep = build(a.glb, a.stem, pal, stamp=not a.no_stamp)
    Path(a.out).write_bytes(kv.to_bytes())
    print(f"{a.out}: {rep}")


if __name__ == "__main__":
    main()
