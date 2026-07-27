#!/usr/bin/env python3
"""Generate the multiplayer BJ sprite set from the guard rotations.

The guard's complete 8-rotation set (stand/walk/pain/shoot/death) is
re-ramped onto BJ's OWN colors, learned from the victory-run frames:
uniform browns -> his grey ramp (luminance-matched), helmet -> his hair
ramp with the stahlhelm brim clamped to the crown width, strap/belt/
collar dissolved into the cloth (index pass + thin-line filter). Output
is build/playersprite/BJP*.png, packed when the multiplayer phase lands.
User-approved look (bj_preview5): decent placeholder-plus; boots stay
guard-blue pending a real art pass.
"""
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image
from wolf_common import ROOT, load_palette

D = ROOT / "build" / "vswap" / "wl6" / "sprites"
OUT = ROOT / "build" / "playersprite"

pal = load_palette()
rgb2idx = {tuple(pal[i]): i for i in range(256)}


def lum(i):
    r, g, b = pal[i]
    return 0.299 * r + 0.587 * g + 0.114 * b


def plum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def hair_colors():
    hair = Counter()
    for ch in range(408, 412):
        im = Image.open(D / f"SPR{ch:03d}.png").convert("RGBA")
        px = im.load()
        bbox = im.split()[3].getbbox()
        for y in range(bbox[1], bbox[1] + 6):
            for x in range(im.width):
                r, g, b, a = px[x, y]
                if a > 0:
                    hair[rgb2idx.get((r, g, b), 0)] += 1
    return sorted([i for i, n in hair.most_common(6) if n > 5], key=lum)


HAIR = None
GREYS = list(range(16, 32))
UNIFORM = {}
for i in range(192, 224):
    t = min(GREYS, key=lambda g: abs(lum(g) - lum(i) * 0.92))
    UNIFORM[tuple(pal[i])] = tuple(pal[t])
DARKMID = pal[0x1C]
STRAPSRC = {tuple(pal[223]), tuple(pal[222]), (0, 0, 0)}


def convert(ch, recolor_head=True):
    im = Image.open(D / f"SPR{ch:03d}.png").convert("RGBA")
    px = im.load()
    bbox = im.split()[3].getbbox()
    if bbox is None:
        return im
    top, bot = bbox[1], bbox[3]
    h = bot - top
    helmet_bottom = top + h // 5
    band_bot = top + 3 * h // 4

    for y in range(helmet_bottom, band_bot):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 0 and (r, g, b) in STRAPSRC:
                px[x, y] = (DARKMID[0], DARKMID[1], DARKMID[2], a)
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r > 180 and b > 180 and g < 120:      # stray magenta
                px[x, y] = (DARKMID[0], DARKMID[1], DARKMID[2], a)
            elif (r, g, b) in UNIFORM:
                nr, ng, nb = UNIFORM[(r, g, b)]
                px[x, y] = (nr, ng, nb, a)
    for _ in range(2):
        for y in range(helmet_bottom, band_bot):
            for x in range(1, im.width - 1):
                p = px[x, y]
                if p[3] == 0 or plum(p) > 62:
                    continue
                lft, rgt = px[x - 1, y], px[x + 1, y]
                up, dn = px[x, y - 1], px[x, y + 1]
                if (lft[3] and rgt[3] and plum(lft) > plum(p) + 22
                        and plum(rgt) > plum(p) + 22):
                    px[x, y] = lft
                elif (up[3] and dn[3] and plum(up) > plum(p) + 22
                        and plum(dn) > plum(p) + 22):
                    px[x, y] = up
    if recolor_head:
        rows = {}
        for y in range(top, helmet_bottom):
            xs = [x for x in range(im.width) if px[x, y][3] > 0]
            if xs:
                rows[y] = (min(xs), max(xs))
        keys = list(rows.keys())
        crown = keys[:max(1, len(keys) * 2 // 5)]
        if crown:
            cw = max(rows[y][1] - rows[y][0] for y in crown) - 1
            for n, y in enumerate(keys):
                x0, x1 = rows[y]
                limit = cw + (1 if n == len(keys) - 1 else 0)
                over = (x1 - x0) - limit
                if over > 0:
                    for k in range(over // 2 + over % 2):
                        px[x0 + k, y] = (0, 0, 0, 0)
                    for k in range(over // 2):
                        px[x1 - k, y] = (0, 0, 0, 0)
        for y in range(top, helmet_bottom):
            for x in range(im.width):
                r, g, b, a = px[x, y]
                if a > 0:
                    c = min(HAIR,
                            key=lambda hh: abs(lum(hh) - plum((r, g, b))))
                    nr, ng, nb = pal[c]
                    px[x, y] = (nr, ng, nb, a)
    return im


def main():
    global HAIR
    HAIR = hair_colors()
    OUT.mkdir(parents=True, exist_ok=True)
    n = 0
    # guard chunk map: stand 50-57(8 rot), walk A-D 58-89, pain 90?,
    # shoot 96-98, die 91-95 - non-rotated frames get suffix 0
    jobs = []
    for r in range(8):
        jobs.append((50 + r, f"BJPA{r + 1}"))            # stand
    for f in range(4):
        for r in range(8):
            jobs.append((58 + f * 8 + r, f"BJP{chr(66 + f)}{r + 1}"))
    for i, ch in enumerate((90, 91, 92, 93, 95)):        # die + dead
        jobs.append((ch, f"BJP{chr(70 + i)}0"))
    for i, ch in enumerate((96, 97, 98)):                # shoot
        jobs.append((ch, f"BJP{chr(75 + i)}0"))
    for ch, name in jobs:
        src = D / f"SPR{ch:03d}.png"
        if not src.exists():
            continue
        convert(ch).save(OUT / f"{name}.png")
        n += 1
    print(f"playersprite: {n} frames generated")


if __name__ == "__main__":
    main()
