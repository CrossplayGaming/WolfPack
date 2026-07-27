#!/usr/bin/env python3
"""Extract the VGAGRAPH text chunks and the proportional font.

The end-of-episode articles (T_ENDART1..6, chunks 143-148) are plain text
in the layout language WL_TEXT.C parses: ^P page, ^C<hex> colour,
^G<y>,<x>,<pic> graphic, ^L<x>,<y> locate, ^E end.

Font chunk 1 (STARTFONT) is a fontstruct: height word, then 256 word
offsets, then 256 byte widths, then 1-byte-per-pixel glyph masks. The
masks are 1-bit (nonzero = draw in the current fontcolor), so each glyph
comes out as a white-on-alpha PNG that the renderer tints.
"""
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image
from wolf_common import ROOT, find_data, huff_expand

OUT = ROOT / "build" / "text"
ENDART = {i: 143 + i for i in range(6)}      # episode 1-6 -> chunk
HELPART = 138                                # T_HELPART (Read This!)
FONT_CHUNKS = {"font": 1, "fontbig": 2}      # STARTFONT, STARTFONT+1


def open_graph(ext):
    hits = find_data(ext)
    if not all(k in hits for k in ("VGADICT", "VGAHEAD", "VGAGRAPH")):
        return None
    raw = hits["VGADICT"].read_bytes()
    nodes = [struct.unpack_from("<2H", raw, i * 4) for i in range(255)]
    head = hits["VGAHEAD"].read_bytes()
    graph = hits["VGAGRAPH"].read_bytes()
    offs = []
    for i in range(len(head) // 3):
        o = head[i * 3] | (head[i * 3 + 1] << 8) | (head[i * 3 + 2] << 16)
        offs.append(None if o == 0xFFFFFF else o)

    def chunk(i):
        o = offs[i]
        if o is None:
            return None
        j = i + 1
        while j < len(offs) and offs[j] is None:
            j += 1
        end = offs[j] if j < len(offs) else len(graph)
        r = graph[o:end]
        (n,) = struct.unpack_from("<i", r, 0)
        return huff_expand(nodes, r[4:], n)

    return chunk


def extract_font(chunk, outdir, name="font", chunknum=1):
    """fontstruct: height, location[256] words, width[256] bytes, masks."""
    data = chunk(chunknum)
    (height,) = struct.unpack_from("<H", data, 0)
    locs = struct.unpack_from("<256H", data, 2)
    widths = struct.unpack_from("<256B", data, 2 + 512)

    gdir = outdir / name
    gdir.mkdir(parents=True, exist_ok=True)
    meta = {"height": height, "widths": {}}
    n = 0
    for c in range(256):
        w = widths[c]
        if w == 0 or locs[c] == 0:
            continue
        src = locs[c]
        img = Image.new("RGBA", (w, height), (0, 0, 0, 0))
        px = img.load()
        for y in range(height):
            for x in range(w):
                if data[src + y * w + x]:
                    px[x, y] = (255, 255, 255, 255)
        # GZDoom folder fonts are named by hex codepoint
        img.save(gdir / f"{c:04x}.png")
        meta["widths"][str(c)] = w
        n += 1
    (outdir / f"{name}.json").write_text(json.dumps(meta))
    print(f"{name}: {n} glyphs, height {height}")


def main():
    chunk = open_graph("WL6")
    if chunk is None:
        sys.exit("no VGAGRAPH data found")
    OUT.mkdir(parents=True, exist_ok=True)

    pics = set()
    for ep, ci in ENDART.items():
        raw = chunk(ci)
        if raw is None:
            continue
        text = raw.decode("latin-1")
        (OUT / f"endart{ep + 1}.txt").write_text(text, encoding="latin-1")
        # collect the ^G pics so make_assets knows what to pack
        i = 0
        while True:
            i = text.find("^G", i)
            if i < 0:
                break
            nums = text[i + 2:text.find("\n", i)].split(",")
            try:
                pics.add(int(nums[2]))
            except (IndexError, ValueError):
                pass
            i += 2
    raw = chunk(HELPART)
    if raw is not None:
        (OUT / "helpart.txt").write_bytes(raw)
    print(f"articles: {len(ENDART)}+help extracted, ^G pics referenced: "
          f"{sorted(pics)}")

    for nm, ch in FONT_CHUNKS.items():
        extract_font(chunk, OUT, nm, ch)


if __name__ == "__main__":
    main()
