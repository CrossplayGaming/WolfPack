#!/usr/bin/env python3
"""Bake a uniform recolor of a voxel pose set.

    python tools/voxel/recolor_vox.py <vox_dir> <out_dir> --variant 2

Player Setup offers four uniforms, and WolfPlayer.ApplySkin already
switches between them by SPRITE INDEX (BJ1x -> BJ2x/BJ3x/BJ4x) rather
than by an engine translation. VOXELDEF binds a voxel to a sprite+frame
token, so a voxel registered as BJ2SA is picked by that same swap with
no new code -- the cost is that each uniform is a baked set of models.

Two rules make the bake safe:

1. ONLY the uniform moves. BJ's coat quantises to near-perfect neutrals
   (saturation 0-2 across the top palette entries), while boots sit at
   saturation ~90, and hair, skin and blood are all strongly coloured.
   A saturation cut therefore separates the uniform cleanly, and nothing
   bleeds into the gun, the boots or the blood spatter.

2. The target hues are the GAME's, not invented: the same Wolf palette
   ramps the sprite recolor uses (gen_playersprite.py RAMPS) -- grey
   0x13-0x1D, blue 0x98-0xA0, red 0x24-0x2C, tan 0xD4-0xDC. Shading is
   preserved by mapping each grey's luminance to its relative position
   in the target ramp, so a shadowed fold stays a shadowed fold.
"""
import argparse
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_vox import read_vox                       # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent

# gen_playersprite.py RAMPS, as palette index spans
RAMPS = {
    1: (0x13, 0x1D),        # grey (BJ classic) - the source
    2: (0x98, 0xA0),        # blue
    3: (0x24, 0x2C),        # red
    4: (0xD4, 0xDC),        # tan
}

# saturation at or below this is "the uniform". Measured: coat entries
# run 0-2, the next-nearest thing (boots) is ~90.
SAT_CUT = 8


def lum(c):
    return (c[0] * 30 + c[1] * 59 + c[2] * 11) // 100


def playpal():
    d = (ROOT / "build/assets/PLAYPAL").read_bytes()
    return [(d[i * 3], d[i * 3 + 1], d[i * 3 + 2]) for i in range(256)]


def ramp_colors(pal, variant):
    lo, hi = RAMPS[variant]
    return sorted((pal[i] for i in range(lo, hi)), key=lum)


def write_vox(dims, vox, pal, out):
    """MagicaVoxel .vox, same layout voxelize.py writes."""
    def chunk(cid, content, children=b""):
        return (cid + struct.pack("<ii", len(content), len(children))
                + content + children)

    size = chunk(b"SIZE", struct.pack("<iii", *dims))
    xyzi = chunk(b"XYZI", struct.pack("<i", len(vox))
                 + b"".join(struct.pack("<4B", *v) for v in vox))
    rgba = chunk(b"RGBA", b"".join(struct.pack("<4B", *c, 255)
                                   for c in pal[:256]))
    body = size + xyzi + rgba
    out.write_bytes(b"VOX " + struct.pack("<i", 150)
                    + chunk(b"MAIN", b"", body))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vox_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--variant", type=int, required=True, choices=[2, 3, 4])
    a = ap.parse_args()

    pal = playpal()
    target = ramp_colors(pal, a.variant)
    src_lo, src_hi = None, None

    src = Path(a.vox_dir)
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    files = sorted(src.glob("*.vox"))
    if not files:
        sys.exit(f"no .vox files in {src}")

    # one luminance span for the WHOLE set, so a dark pose does not get
    # a differently-stretched uniform from a bright one
    for f in files:
        _dims, vox, vpal = read_vox(f)
        used = {v[3] for v in vox}
        for i in used:
            c = vpal[i - 1][:3]
            if max(c) - min(c) <= SAT_CUT:
                L = lum(c)
                src_lo = L if src_lo is None else min(src_lo, L)
                src_hi = L if src_hi is None else max(src_hi, L)
    if src_lo is None:
        sys.exit("no uniform (low-saturation) colours found")
    print(f"uniform luminance span {src_lo}-{src_hi} -> "
          f"{len(target)}-step ramp {RAMPS[a.variant]}")

    for f in files:
        dims, vox, vpal = read_vox(f)
        newpal, moved = [], 0
        for i in range(256):
            c = vpal[i][:3]
            if max(c) - min(c) <= SAT_CUT and src_lo <= lum(c) <= src_hi:
                t = (lum(c) - src_lo) / max(1, src_hi - src_lo)
                newpal.append(target[min(len(target) - 1,
                                         int(t * len(target)))])
                moved += 1
            else:
                newpal.append(c)
        write_vox(dims, vox, newpal, out / f.name)
        print(f"  {f.name}: {moved} palette entries recoloured")

    for extra in ("frame.json", "frames.json"):
        p = src / extra
        if p.exists():
            (out / extra).write_bytes(p.read_bytes())
            print(f"  carried {extra}")


if __name__ == "__main__":
    main()
