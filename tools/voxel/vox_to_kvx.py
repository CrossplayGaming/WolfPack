#!/usr/bin/env python3
"""MagicaVoxel .vox -> Build KVX, the engine's voxel format.

    python tools/voxel/vox_to_kvx.py <in.vox|dir> <out_dir> --name MILO
                                     [--sprite-dir <dir>]

The queued engine-proof piece of the voxel chain: UZDoom consumes KVX
via VOXELDEF (the Cheello path), not MagicaVoxel .vox. Given a single
.vox or a directory of pose .vox files (sorted), writes one KVX per
pose named <name><letter>.kvx -- MILOA, MILOB, ... -- which is exactly
the sprite-frame naming VOXELDEF binds to.

Also writes <name><letter>0.png placeholder sprites (front projection,
grAb offsets at bottom-center): the engine requires the sprite frame to
EXIST for the state to be valid; the voxel then replaces its rendering.

Format facts (SLAB6 kvx spec):
  * z grows DOWN from the top; our .vox z grows up -> kz = (zs-1)-z.
  * per-column slab runs: ztop, zleng, cullinfo, then zleng palette
    bytes. Cull bits: 1 -x, 2 +x, 4 -y, 8 +y, 16 up, 32 down. Maximal
    runs always expose up+down; sides are OR'd over the run (slab6's
    own convention -- over-marking draws a hidden face, never drops a
    visible one).
  * offset tables are relative to the START of the xoffset table:
    xoffset[0] == (xs+1)*4 + xs*(ys+1)*2. xyoffset entries are uint16
    relative to their x-slice, so one slice must stay under 64K.
  * palette trails the file: 256 RGB triples, 6-bit (0-63).
  * pivots are 8.8 fixed point; bottom-center puts the actor's feet at
    the thing origin, same as a Doom sprite.

Self-verifying (the .vox writer lesson, 2026-08-02: previews rendered
from in-memory data cannot catch a writer fault): after writing, the
KVX is parsed back like a reader would and the voxel count and per-
voxel colours are compared against the input. A mismatch fails loudly.
"""
import argparse
import struct
import sys
from pathlib import Path

from PIL import Image
from PIL.PngImagePlugin import PngInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_vox import read_vox                     # noqa: E402


def vox_solid(path):
    dims, vox, pal = read_vox(path)
    solid = {(x, y, z): pal[c - 1][:3] if pal and c >= 1 else (255, 0, 255)
             for x, y, z, c in vox}
    return solid, dims


def to_kvx(solid, dims, out, origin=None):
    """origin: rig-origin in voxel coords (from a pose set's
    frame.json). Without it the pivot falls back to bounding-box
    bottom-center -- right for symmetric single poses, wrong for sets
    whose union box is dominated by a sprawled pose (a death): the
    box-center pivot would shift the standing frames sideways."""
    xs, ys, zs = dims
    assert max(dims) <= 256, f"KVX is byte-addressed; dims {dims} too big"

    colors = sorted({c for c in solid.values()})
    assert len(colors) <= 256, f"{len(colors)} colours; palette holds 256"
    pidx = {c: i for i, c in enumerate(colors)}

    # z-down grid keyed for neighbour tests and column walks
    k = {(x, y, (zs - 1) - z): c for (x, y, z), c in solid.items()}

    tables = (xs + 1) * 4 + xs * (ys + 1) * 2
    xoffset = [tables]
    xyoffset = []
    voxdata = bytearray()
    for x in range(xs):
        slice_start = len(voxdata)
        for y in range(ys):
            xyoffset.append(len(voxdata) - slice_start)
            zlist = sorted(kz for (kx, ky, kz) in k if kx == x and ky == y)
            i = 0
            while i < len(zlist):
                j = i
                while j + 1 < len(zlist) and zlist[j + 1] == zlist[j] + 1:
                    j += 1
                ztop, zlen = zlist[i], j - i + 1
                cull = 16 | 32          # maximal run: up and down exposed
                for kz in zlist[i:j + 1]:
                    if (x - 1, y, kz) not in k:
                        cull |= 1
                    if (x + 1, y, kz) not in k:
                        cull |= 2
                    if (x, y - 1, kz) not in k:
                        cull |= 4
                    if (x, y + 1, kz) not in k:
                        cull |= 8
                voxdata += bytes((ztop, zlen, cull))
                voxdata += bytes(pidx[k[(x, y, kz)]]
                                 for kz in zlist[i:j + 1])
                i = j + 1
        xyoffset.append(len(voxdata) - slice_start)
        assert xyoffset[-1] < 65536, f"x-slice {x} exceeds 64K of slab data"
        xoffset.append(tables + len(voxdata))

    if origin is not None:
        # z pivot converts to KVX's z-down space: world z=0 (feet) sits
        # at kz = zs-1-origin_z
        piv = (int(origin[0] * 256), int(origin[1] * 256),
               int((zs - 1 - origin[2]) * 256))
    else:
        piv = ((xs << 8) // 2, (ys << 8) // 2, zs << 8)

    numbytes = 24 + tables + len(voxdata)
    buf = bytearray()
    buf += struct.pack("<i", numbytes)
    buf += struct.pack("<3i", xs, ys, zs)
    buf += struct.pack("<3i", piv[0], piv[1], piv[2])
    buf += struct.pack(f"<{len(xoffset)}i", *xoffset)
    buf += struct.pack(f"<{len(xyoffset)}H", *xyoffset)
    buf += voxdata
    for i in range(256):
        c = colors[i] if i < len(colors) else (0, 0, 0)
        buf += bytes((c[0] >> 2, c[1] >> 2, c[2] >> 2))
    Path(out).write_bytes(buf)
    return len(colors)


def read_back_kvx(path):
    """Parse a KVX the way a reader would; return {(x,y,kz): (r,g,b)}
    with the palette's 6->8 bit loss, for verification."""
    d = Path(path).read_bytes()
    xs, ys, zs = struct.unpack("<3i", d[4:16])
    pal_raw = d[-768:]
    pal = [tuple(min(255, v << 2) for v in pal_raw[i * 3:i * 3 + 3])
           for i in range(256)]
    off = 28
    xoffset = struct.unpack(f"<{xs + 1}i", d[off:off + (xs + 1) * 4])
    off += (xs + 1) * 4
    xy = struct.unpack(f"<{xs * (ys + 1)}H", d[off:off + xs * (ys + 1) * 2])
    table_start = 28
    out = {}
    for x in range(xs):
        for y in range(ys):
            a = table_start + xoffset[x] + xy[x * (ys + 1) + y]
            b = table_start + xoffset[x] + xy[x * (ys + 1) + y + 1]
            while a < b:
                ztop, zlen = d[a], d[a + 1]
                for i in range(zlen):
                    out[(x, y, ztop + i)] = pal[d[a + 3 + i]]
                a += 3 + zlen
    return out, (xs, ys, zs)


def verify(solid, dims, kvx_path):
    got, gdims = read_back_kvx(kvx_path)
    xs, ys, zs = dims
    assert gdims == tuple(dims), f"dims {gdims} != {tuple(dims)}"
    want = {(x, y, (zs - 1) - z): c for (x, y, z), c in solid.items()}
    assert len(got) == len(want), \
        f"voxel count {len(got)} != {len(want)} -- slabs dropped voxels"
    bad = sum(1 for key, c in want.items()
              if max(abs(a - b) for a, b in zip(got[key], c)) > 3)
    assert bad == 0, f"{bad} voxels came back the wrong colour"


def sprite_png(solid, dims, out):
    """Front projection (viewer at -y) at 1:1 scale, with grAb offsets
    at bottom-center so the fallback sprite stands where the voxel
    will."""
    xs, ys, zs = dims
    img = Image.new("RGBA", (xs, zs), (0, 0, 0, 0))
    best = {}
    for (x, y, z), c in solid.items():
        if (x, z) not in best or y < best[(x, z)][0]:
            best[(x, z)] = (y, c)
    for (x, z), (_, c) in best.items():
        img.putpixel((x, zs - 1 - z), (*c, 255))
    info = PngInfo()
    info.add(b"grAb", struct.pack(">ii", xs // 2, zs))
    img.save(out, pnginfo=info)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help=".vox file or directory of pose .vox files")
    ap.add_argument("out_dir")
    ap.add_argument("--name", required=True,
                    help="4-char sprite name; poses become <name>A, <name>B..")
    ap.add_argument("--sprite-dir", default=None,
                    help="where placeholder sprites go (default out_dir)")
    a = ap.parse_args()
    assert len(a.name) == 4, "sprite names are exactly 4 characters"

    src = Path(a.src)
    voxes = sorted(src.glob("*.vox")) if src.is_dir() else [src]
    if not voxes:
        sys.exit(f"no .vox files under {src}")
    out_dir = Path(a.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    spr_dir = Path(a.sprite_dir) if a.sprite_dir else out_dir
    spr_dir.mkdir(parents=True, exist_ok=True)

    import json
    base = src if src.is_dir() else src.parent

    origin = None
    fj = base / "frame.json"
    if fj.exists():
        origin = json.loads(fj.read_text())["origin_voxel"]
        print(f"pivot from frame.json: rig origin at "
              f"({origin[0]:.1f}, {origin[1]:.1f}, {origin[2]:.1f})")

    # PER-POSE pivots. A per-pose set has no shared frame: every pose is
    # boxed on its own extents, so the box bears no fixed relationship
    # to the body -- extend the gun and the box grows forward, sliding
    # the body backwards under a box-centre pivot. Measured on BJ's
    # shooting clip: the feet moved 12.4 voxels (~7 map units) across
    # five poses, i.e. he skated. frames.json (from anchor_poses.py)
    # carries one origin per pose so the anchor can be a body landmark.
    per_pose = {}
    pj = base / "frames.json"
    if pj.exists():
        per_pose = json.loads(pj.read_text())
        print(f"per-pose pivots from frames.json ({len(per_pose)} poses)")

    for i, vp in enumerate(voxes):
        frame = chr(ord("A") + i)
        solid, dims = vox_solid(vp)
        kvx = out_dir / f"{a.name}{frame}.kvx"
        org = per_pose.get(vp.stem, origin)
        if vp.stem in per_pose:
            print(f"  {vp.stem}: pivot ({org[0]:.1f}, {org[1]:.1f}, "
                  f"{org[2]:.1f})")
        ncol = to_kvx(solid, dims, kvx, org)
        verify(solid, dims, kvx)
        sprite_png(solid, dims, spr_dir / f"{a.name}{frame}0.png")
        print(f"{vp.name} -> {kvx.name}  {len(solid)} voxels, "
              f"{ncol} colours, dims {dims}  [verified]")


if __name__ == "__main__":
    main()
