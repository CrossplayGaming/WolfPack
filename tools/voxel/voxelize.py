#!/usr/bin/env python3
"""Textured OBJ -> coloured voxels, no external tools.

    python tools/voxel/voxelize.py <in.obj> <out_stem> [--height 32]
                                   [--ega]

Own voxelizer, project-style (we write binary formats for breakfast):
parses the OBJ+MTL+texture directly, rasterises every triangle into a
voxel grid by barycentric sampling, colours each voxel from the UV
texture, optionally quantises to EGA16, and writes:

  <out_stem>.vox        MagicaVoxel file (open/tweak in MagicaVoxel)
  <out_stem>_slices.png contact sheet of horizontal slices (fast eyeball)
  <out_stem>_views.png  front/side/top orthographic previews

The whole Meshy chain: GLB -> (glb_to_obj.py) -> OBJ -> here -> .vox
-> KVX (converter next) -> VOXELDEF in the shell.
"""
import argparse
import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
# --ega is a Crystal Caves flag: that game's art IS 16-colour EGA. Wolf's
# is 256-colour VGA, so the palette module is not vendored here and the
# flag simply refuses. --sprite <png> is the Wolf path (quantise to an
# actual game sprite's own colours).
try:
    from ccformats.palette import EGA16           # noqa: E402
except ModuleNotFoundError:
    EGA16 = None


def parse_obj(path):
    path = Path(path)
    verts, uvs, faces = [], [], []
    mtl_tex = {}
    cur_tex = None
    for line in path.read_text(errors="replace").splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "mtllib":
            mtl_path = path.parent / " ".join(p[1:])
            if mtl_path.exists():
                name = None
                for ml in mtl_path.read_text(errors="replace").splitlines():
                    mp = ml.split()
                    if not mp:
                        continue
                    if mp[0] == "newmtl":
                        name = " ".join(mp[1:])
                    elif mp[0] == "map_Kd" and name:
                        mtl_tex[name] = path.parent / " ".join(mp[1:])
        elif p[0] == "usemtl":
            cur_tex = mtl_tex.get(" ".join(p[1:]))
        elif p[0] == "v":
            verts.append(tuple(float(x) for x in p[1:4]))
        elif p[0] == "vt":
            uvs.append((float(p[1]), float(p[2])))
        elif p[0] == "f":
            idx = []
            for w in p[1:]:
                comp = w.split("/")
                vi = int(comp[0])
                ti = int(comp[1]) if len(comp) > 1 and comp[1] else 0
                idx.append((vi - 1, ti - 1))
            for k in range(1, len(idx) - 1):
                faces.append((idx[0], idx[k], idx[k + 1], cur_tex))
    return verts, uvs, faces


def obj_bounds(verts):
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def voxelize(verts, uvs, faces, height, frame=None):
    """frame=(mins, maxs, scale): a SHARED transform for a pose SET.
    Without it each pose is normalized to its own bounding box -- fine
    for cycles that stay one shape (run, idle), wrong for a death: the
    lying pose's short z-span would blow up to full height and every
    pose would recenter, so the body slides between frames. One frame
    for the whole set = one scale, one grid, one pivot: registration."""
    if frame is None:
        mins, maxs = obj_bounds(verts)
        span = max(maxs[2] - mins[2], 1e-9)
        scale = (height - 1) / span
    else:
        mins, maxs, scale = frame
    dims = [max(1, int(round((mx - mn) * scale)) + 1)
            for mn, mx in zip(mins, maxs)]

    textures = {}
    grid = {}
    for (a, ta), (b, tb), (c, tc), tex in faces:
        pa, pb, pc = verts[a], verts[b], verts[c]
        img = None
        if tex is not None:
            if tex not in textures:
                textures[tex] = Image.open(tex).convert("RGB") \
                    if Path(tex).exists() else None
            img = textures[tex]
        # sample density ~2 per voxel across the triangle
        import math
        e1 = math.dist(pa, pb) * scale
        e2 = math.dist(pa, pc) * scale
        n = max(2, int(max(e1, e2)) * 2 + 1)
        for i in range(n + 1):
            for j in range(n + 1 - i):
                u = i / n
                v = j / n
                w = 1 - u - v
                x = pa[0] * w + pb[0] * u + pc[0] * v
                y = pa[1] * w + pb[1] * u + pc[1] * v
                z = pa[2] * w + pb[2] * u + pc[2] * v
                key = (min(dims[0] - 1, max(0, int((x - mins[0]) * scale + 0.5))),
                       min(dims[1] - 1, max(0, int((y - mins[1]) * scale + 0.5))),
                       min(dims[2] - 1, max(0, int((z - mins[2]) * scale + 0.5))))
                if img is not None and ta >= 0:
                    tu = uvs[ta][0] * w + uvs[tb][0] * u + uvs[tc][0] * v
                    tv = uvs[ta][1] * w + uvs[tb][1] * u + uvs[tc][1] * v
                    px = img.getpixel(
                        (min(img.width - 1,
                             max(0, int(tu % 1.0 * img.width))),
                         min(img.height - 1,
                             max(0, int((1 - tv % 1.0) * img.height)))))
                else:
                    px = (200, 200, 200)
                grid.setdefault(key, []).append(px)
    solid = {k: tuple(sum(c[i] for c in v) // len(v) for i in range(3))
             for k, v in grid.items()}
    return solid, dims


def ega_quantize(solid):
    if EGA16 is None:
        sys.exit("--ega needs ccformats.palette (Crystal Caves only); "
                 "use --sprite <png> for Wolf art")

    def nearest(px):
        return min(EGA16, key=lambda e: sum((a - b) ** 2
                                            for a, b in zip(e, px)))
    return {k: nearest(v) for k, v in solid.items()}


def sprite_quantize(solid, sprite_png):
    """Quantize to the ORIGINAL SPRITE's own colours, with the model's
    shading range stretched across them by luminance -- so a Meshy
    render's subtle facets become the sprite's own highlight colours
    instead of collapsing into one EGA shade."""
    img = Image.open(sprite_png).convert("RGBA")
    cols = sorted({p[:3] for p in img.getdata() if p[3] > 0},
                  key=lambda c: 0.299 * c[0] + 0.587 * c[1]
                  + 0.114 * c[2])
    if not cols:
        return solid

    def luma(c):
        return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]

    lumas = [luma(v) for v in solid.values()]
    lo, hi = min(lumas), max(lumas)
    span = max(hi - lo, 1e-9)
    out = {}
    for k, v in solid.items():
        t = (luma(v) - lo) / span
        out[k] = cols[min(len(cols) - 1, int(t * len(cols)))]
    return out


def write_vox(solid, dims, out):
    # .vox carries at most 255 palette entries. Truncating a full-colour
    # model's unique colours DROPS every voxel whose colour missed the
    # cut -- and sorting RGB tuples keeps the darkest, so a model loaded
    # as its own shadow (measured 2026-08-02). Quantise properly instead:
    # median-cut to <=255, every voxel keeps a colour.
    uniq = sorted({c for c in solid.values()})
    if len(uniq) <= 255:
        palette = uniq
        pidx = {c: i + 1 for i, c in enumerate(palette)}
    else:
        strip = Image.new("RGB", (len(uniq), 1))
        strip.putdata(uniq)
        q = strip.quantize(colors=255, method=Image.MEDIANCUT)
        pal = q.getpalette()[:255 * 3]
        palette = [tuple(pal[i * 3:i * 3 + 3]) for i in range(255)]
        pidx = {c: q.getdata()[i] + 1 for i, c in enumerate(uniq)}
    voxels = [(x, y, z, pidx[c]) for (x, y, z), c in solid.items()]

    def chunk(cid, content, children=b""):
        return (cid + struct.pack("<ii", len(content), len(children))
                + content + children)

    size = chunk(b"SIZE", struct.pack("<iii", *dims))
    xyzi = chunk(b"XYZI", struct.pack("<i", len(voxels))
                 + b"".join(struct.pack("<4B", x, y, z, i)
                            for x, y, z, i in voxels))
    rgba = b""
    for i in range(256):
        c = palette[i] if i < len(palette) else (0, 0, 0)
        rgba += struct.pack("<4B", *c, 255)
    rgba = chunk(b"RGBA", rgba)
    main = chunk(b"MAIN", b"", size + xyzi + rgba)
    Path(out).write_bytes(b"VOX " + struct.pack("<i", 150) + main)


def previews(solid, dims, stem):
    S = 6
    # slice sheet
    cols = min(8, dims[2])
    rows = (dims[2] + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (dims[0] * S + 4),
                              rows * (dims[1] * S + 4)), (24, 20, 16))
    for z in range(dims[2]):
        img = Image.new("RGB", (dims[0], dims[1]), (10, 10, 10))
        for (x, y, zz), c in solid.items():
            if zz == z:
                img.putpixel((x, dims[1] - 1 - y), c)
        img = img.resize((dims[0] * S, dims[1] * S), Image.NEAREST)
        sheet.paste(img, ((z % cols) * (dims[0] * S + 4),
                          (z // cols) * (dims[1] * S + 4)))
    sheet.save(f"{stem}_slices.png")
    # ortho views: front (x/z), side (y/z), top (x/y)
    views = []
    for axes in (((0, 2), 1), ((1, 2), 0), ((0, 1), 2)):
        (ax, ay), depth = axes
        img = Image.new("RGB", (dims[ax], dims[ay]), (10, 10, 10))
        best = {}
        for key, c in solid.items():
            k2 = (key[ax], key[ay])
            if k2 not in best or key[depth] < best[k2][0]:
                best[k2] = (key[depth], c)
        for (px, py), (_, c) in best.items():
            img.putpixel((px, img.height - 1 - py), c)
        views.append(img.resize((dims[ax] * S, dims[ay] * S),
                                Image.NEAREST))
    w = sum(v.width for v in views) + 20
    h = max(v.height for v in views)
    combo = Image.new("RGB", (w, h), (24, 20, 16))
    x = 0
    for v in views:
        combo.paste(v, (x, h - v.height))
        x += v.width + 10
    combo.save(f"{stem}_views.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("obj")
    ap.add_argument("out_stem")
    ap.add_argument("--height", type=int, default=32)
    ap.add_argument("--ega", action="store_true")
    ap.add_argument("--sprite", help="quantize to this sprite PNG's own "
                                     "colours, shading stretched by "
                                     "luminance")
    ap.add_argument("--match", help="another set's frame.json: reuse its "
                                    "scale so the character stays ONE size "
                                    "across sets (a jump clip's union span "
                                    "includes the flight arc, which would "
                                    "shrink the body ~15%%)")
    ap.add_argument("--per-pose", action="store_true",
                    help="airborne sets: per-pose bounds instead of a "
                         "union frame. Each pose self-grounds (its lowest "
                         "point = actor origin) so the clip's baked root "
                         "motion doesn't double with the engine's physics")
    a = ap.parse_args()

    def finish(solid, dims, stem):
        if a.sprite:
            solid = sprite_quantize(solid, a.sprite)
        elif a.ega:
            solid = ega_quantize(solid)
        write_vox(solid, dims, stem + ".vox")
        previews(solid, dims, stem)
        print(f"{Path(stem).name}: {len(solid)} voxels in {dims}")

    src = Path(a.obj)
    if src.is_dir():
        # Pose SET: one shared frame (union bounds, scale from the
        # union z-span -- i.e. the tallest pose defines the height) so
        # every pose lands registered on the same grid.
        objs = sorted(src.glob("*.obj"))
        if not objs:
            sys.exit(f"no .obj files under {src}")
        parsed = [parse_obj(p) for p in objs]
        bounds = [obj_bounds(v) for v, _, _ in parsed]
        mins = tuple(min(b[0][i] for b in bounds) for i in range(3))
        maxs = tuple(max(b[1][i] for b in bounds) for i in range(3))
        if a.match:
            import json
            scale = json.loads(Path(a.match).read_text())["scale"]
        else:
            scale = (a.height - 1) / max(maxs[2] - mins[2], 1e-9)
        out_dir = Path(a.out_stem)
        out_dir.mkdir(parents=True, exist_ok=True)
        if a.per_pose:
            print(f"per-pose frames at matched scale {scale:.2f} vox/unit, "
                  f"{len(objs)} poses")
            for p, ((verts, uvs, faces), (bmin, bmax)) in zip(
                    objs, zip(parsed, bounds)):
                solid, dims = voxelize(verts, uvs, faces, a.height,
                                       frame=(bmin, bmax, scale))
                finish(solid, dims, str(out_dir / p.stem))
            return
        # Record where the RIG ORIGIN (Blender scene origin: feet
        # center) lands in voxel coords. A pose set's union box is
        # dominated by its widest pose (a corpse sprawl), so a
        # box-center pivot would shift every standing frame sideways;
        # the KVX converter pivots on this origin instead, keeping all
        # sets of one character mutually registered.
        import json
        (out_dir / "frame.json").write_text(json.dumps({
            "origin_voxel": [(0 - mins[0]) * scale,
                             (0 - mins[1]) * scale,
                             (0 - mins[2]) * scale],
            "scale": scale, "height": a.height}, indent=1))
        print(f"set frame: z-span {maxs[2] - mins[2]:.2f} -> "
              f"{a.height} voxels, {len(objs)} poses")
        for p, (verts, uvs, faces) in zip(objs, parsed):
            solid, dims = voxelize(verts, uvs, faces, a.height,
                                   frame=(mins, maxs, scale))
            finish(solid, dims, str(out_dir / p.stem))
    else:
        verts, uvs, faces = parse_obj(src)
        solid, dims = voxelize(verts, uvs, faces, a.height)
        finish(solid, dims, a.out_stem)


if __name__ == "__main__":
    main()
