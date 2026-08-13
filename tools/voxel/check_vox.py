#!/usr/bin/env python3
"""Round-trip check: read a .vox back and render what a READER sees.

    python tools/voxel/check_vox.py <file.vox> [out.png]

Written after a writer bug shipped models that previewed perfectly and
loaded into MagicaVoxel as their own shadow: the previews came from the
in-memory voxels, so they could not catch a WRITER fault. This parses
the file like any other reader would and renders from that -- the only
check that can fail on a bad write.
"""
import struct
import sys
from pathlib import Path

from PIL import Image


def read_vox(path):
    d = Path(path).read_bytes()
    if d[:4] != b"VOX ":
        raise SystemExit("not a .vox file")
    i = d.find(b"SIZE")
    dims = struct.unpack("<iii", d[i + 12:i + 24])
    i = d.find(b"XYZI")
    n = struct.unpack("<i", d[i + 12:i + 16])[0]
    vox = [struct.unpack("<4B", d[i + 16 + k * 4:i + 20 + k * 4])
           for k in range(n)]
    i = d.find(b"RGBA")
    pal = [struct.unpack("<4B", d[i + 12 + k * 4:i + 16 + k * 4])
           for k in range(256)] if i >= 0 else []
    return dims, vox, pal


def main():
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else str(Path(src).with_name(
        Path(src).stem + "_readback.png"))
    dims, vox, pal = read_vox(src)
    solid = {(x, y, z): pal[c - 1][:3] if pal and c >= 1 else (255, 0, 255)
             for x, y, z, c in vox}
    print(f"{Path(src).name}: dims {dims}, {len(vox)} voxels, "
          f"{len({v[3] for v in vox})} palette indices used")

    S = 6
    views = []
    for (ax, ay), depth in (((0, 2), 1), ((1, 2), 0), ((0, 1), 2)):
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
    combo = Image.new("RGB", (w, h), (22, 20, 16))
    x = 0
    for v in views:
        combo.paste(v, (x, h - v.height))
        x += v.width + 10
    combo.save(out)
    print("->", out)


if __name__ == "__main__":
    main()
