#!/usr/bin/env python3
"""Phase 1: extract VGAGRAPH (menu/HUD art: status bar, faces, fonts, keys).

VGADICT = 255 huffman nodes x 4 bytes; VGAHEAD = 3-byte offsets;
VGAGRAPH chunks (first i32 of each compressed chunk = expanded length).
Chunk 0 = pictable: {u16 width, u16 height} per pic (NUMPICS entries).
Pics are 4-plane VGA: pixel(x,y) = data[p*(w*h/4) + y*(w/4) + x/4], p=x&3.
Chunk names parsed from GFXV_WL6.H / GFXV_SOD.H.

Output: build/vgagraph/<set>/<NAME>.png (paletted).
"""
import re
import struct
import sys
from pathlib import Path

from PIL import Image

from wolf_common import ROOT, find_data, huff_expand, load_palette

SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"
OUT = ROOT / "build" / "vgagraph"


def parse_enum(header):
    """Return {index: NAME} for the graphics chunk enum (index = enum value)."""
    text = (SRC / header).read_text(errors="replace")
    names = {}
    for name, num in re.findall(r"(\w+PIC|\w+PALETTE|\w+_LUMP_\w+|ORDERSCREEN|ERRORSCREEN|"
                                r"T_\w+|STARTFONT\w*|STARTTILE8M?)\s*,?\s*//\s*(\d+)",
                                text):
        names[int(num)] = name
    return names


def load_dict(path):
    raw = path.read_bytes()
    nodes = []
    for i in range(255):
        b0, b1 = struct.unpack_from("<2H", raw, i * 4)
        nodes.append((b0, b1))
    return nodes


def extract_set(setname, ext, header):
    hits = find_data(ext)
    if not all(k in hits for k in ("VGADICT", "VGAHEAD", "VGAGRAPH")):
        return False
    nodes = load_dict(hits["VGADICT"])
    head = hits["VGAHEAD"].read_bytes()
    graph = hits["VGAGRAPH"].read_bytes()
    offsets = []
    for i in range(len(head) // 3):
        o = head[i * 3] | (head[i * 3 + 1] << 8) | (head[i * 3 + 2] << 16)
        offsets.append(o if o != 0xFFFFFF else None)

    def chunk(i):
        o = offsets[i]
        if o is None:
            return None
        j = i + 1
        while j < len(offsets) and offsets[j] is None:
            j += 1
        end = offsets[j] if j < len(offsets) else len(graph)
        raw = graph[o:end]
        (explen,) = struct.unpack_from("<i", raw, 0)
        return huff_expand(nodes, raw[4:], explen)

    # chunk 0 = pictable
    table = chunk(0)
    npics = len(table) // 4
    sizes = [struct.unpack_from("<2H", table, i * 4) for i in range(npics)]

    names = parse_enum(header)
    pal = load_palette()
    flat = []
    for r, g, b in pal:
        flat += [r, g, b]

    out = OUT / setname
    out.mkdir(parents=True, exist_ok=True)
    # pics start at enum value 3 (STARTPICS after two fonts + ...): the
    # pictable indexes pics by (chunk - STARTPICS); STARTPICS = 3 in both
    # games (chunk 0 pictable is separate; fonts at 1,2).
    STARTPICS = 3
    n = 0
    for ci, name in sorted(names.items()):
        if not name.endswith("PIC"):
            continue
        pi = ci - STARTPICS
        if pi < 0 or pi >= npics:
            continue
        data = chunk(ci)
        if data is None:
            continue
        w, h = sizes[pi]
        if w * h == 0 or len(data) < w * h:
            continue
        img = Image.new("P", (w, h))
        px = img.load()
        q = (w * h) // 4
        for y in range(h):
            for x in range(w):
                px[x, y] = data[(x & 3) * q + y * (w // 4) + x // 4]
        img.putpalette(flat)
        img.save(out / f"{name}.png")
        n += 1

    # Spear's ending screens each carry their OWN VGA palette chunk
    # (END1..END9PALETTE); decoded against the game palette they come
    # out miscoloured, so remap each to its own (EndSpear, WL_INTER.C)
    # Spear's TITLE halves carry their own palette too - decoded against
    # the game palette the title art came out looking like a photo
    # negative (user repro). Any pic with a matching *PALETTE chunk
    # belongs in this table.
    ENDPAL = {"TITLE1PIC": "TITLEPALETTE", "TITLE2PIC": "TITLEPALETTE",
              "ENDSCREEN11PIC": "END1PALETTE", "ENDSCREEN3PIC": "END3PALETTE",
              "ENDSCREEN4PIC": "END4PALETTE", "ENDSCREEN5PIC": "END5PALETTE",
              "ENDSCREEN6PIC": "END6PALETTE", "ENDSCREEN7PIC": "END7PALETTE",
              "ENDSCREEN8PIC": "END8PALETTE", "ENDSCREEN9PIC": "END9PALETTE",
              "ENDSCREEN12PIC": "END2PALETTE"}
    byname = {v: k for k, v in names.items()}
    npal = 0
    for picname, palname in ENDPAL.items():
        f = out / f"{picname}.png"
        ci = byname.get(palname)
        if ci is None or not f.exists():
            continue
        raw = chunk(ci)
        if raw is None or len(raw) < 768:
            continue
        # 6-bit VGA -> 8-bit, same conversion as the game palette
        pal = []
        for i in range(256):
            r, g, b = raw[i * 3], raw[i * 3 + 1], raw[i * 3 + 2]
            pal += [(r * 255) // 63, (g * 255) // 63, (b * 255) // 63]
        img = Image.open(f)
        img.putpalette(pal)
        img.save(f)
        npal += 1
    if npal:
        print(f"{setname}: {npal} screens repalettised "
              "(title + endings)")
    print(f"{setname}: {n} pics extracted")
    return True


def main():
    done = 0
    if extract_set("wl6", "WL6", "GFXV_WL6.H"):
        done += 1
    if extract_set("sod", "SOD", "GFXV_SOD.H"):
        done += 1
    if not done:
        sys.exit("no VGAGRAPH data found")


if __name__ == "__main__":
    main()
