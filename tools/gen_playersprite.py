#!/usr/bin/env python3
"""Generate the multiplayer player sprites from the MUTANT set (user
insight: no helmet, no strap, and a flat-top that is already BJ's
haircut - far less surgery than the guard).

Per frame: dark flat-top -> BJ's hair ramp (sampled from his victory-run
art), pale face/hands -> his flesh ramp, red eyes cleared, the green
tunic rank-normalized onto a clothing ramp, and the chest-embedded gun
filled with neighbouring cloth (the held gun stays - players carry
guns). Four clothing variants for player customization: grey, blue,
red, tan. Output build/playersprite/BJ<v><frame>.png for all 65 mutant
frames (stand/walk/attack/pain/death), packed when multiplayer lands.
Approved look: dist/bjm_v3.png.
"""
import json
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


def sample_bj():
    face, hairc = Counter(), Counter()
    for ch in range(408, 412):
        im = Image.open(D / f"SPR{ch:03d}.png").convert("RGBA")
        px = im.load()
        bb = im.split()[3].getbbox()
        for y in range(bb[1], bb[1] + 12):
            for x in range(im.width):
                r, g, b, a = px[x, y]
                if a > 0:
                    i = rgb2idx.get((r, g, b), 0)
                    if y < bb[1] + 6:
                        hairc[i] += 1
                    elif r > 140 and g > 90 and b < 140:
                        face[i] += 1
    hair = sorted([i for i, n in hairc.most_common(6) if n > 5], key=lum)
    flesh = sorted([i for i, n in face.most_common(6) if n > 3], key=lum)
    return hair, flesh


HAIR, FLESH = None, None


def ramp(lo, hi):
    return sorted(range(lo, hi), key=lum)


RAMPS = {
    "1": ramp(0x13, 0x1D),      # grey (BJ classic)
    "2": ramp(0x98, 0xA0),      # blue
    "3": ramp(0x24, 0x2C),      # red
    "4": ramp(0xD4, 0xDC),      # tan
}


def green_span():
    gl = []
    im = Image.open(D / "SPR187.png").convert("RGBA")
    px = im.load()
    for y in range(64):
        for x in range(64):
            r, g, b, a = px[x, y]
            if a > 0 and g > r + 20 and g > b + 20:
                gl.append(plum((r, g, b)))
    return min(gl), max(gl)


GMIN = GMAX = 0


def convert(ch, cloth_ramp):
    im = Image.open(D / f"SPR{ch:03d}.png").convert("RGBA")
    px = im.load()
    bb = im.split()[3].getbbox()
    if not bb:
        return im
    top, bot = bb[1], bb[3]
    h = bot - top
    head_bot = top + h // 6
    face_bot = top + h // 4
    chest_top, chest_bot = top + h // 4, top + h // 2
    cloth_set = {pal[c] for c in cloth_ramp}

    def cloth_for(v):
        t = (v - GMIN) / max(1, GMAX - GMIN)
        return pal[cloth_ramp[min(len(cloth_ramp) - 1,
                                  int(t * len(cloth_ramp)))]]

    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            mx, mn = max(r, g, b), min(r, g, b)
            if y < head_bot and plum((r, g, b)) < 95:
                c = min(HAIR,
                        key=lambda hh: abs(lum(hh) - plum((r, g, b)) - 90))
                px[x, y] = pal[c] + (a,)
            elif y < face_bot and mx > 150 and mx - mn < 40:
                c = FLESH[min(len(FLESH) - 1,
                              int(plum((r, g, b)) / 300 * len(FLESH)))]
                px[x, y] = pal[c] + (a,)
            elif y < face_bot and r > 150 and g < 90:
                px[x, y] = pal[FLESH[len(FLESH) // 2]] + (a,)
            elif y >= face_bot and mx > 130 and mx - mn < 35:
                c = FLESH[min(len(FLESH) - 1,
                              int(plum((r, g, b)) / 300 * len(FLESH)))]
                px[x, y] = pal[c] + (a,)
            elif g > r + 20 and g > b + 20:
                px[x, y] = cloth_for(plum((r, g, b))) + (a,)

    for _ in range(3):
        for y in range(chest_top, chest_bot):
            for x in range(3, im.width - 3):
                p = px[x, y]
                if p[3] == 0 or plum(p) > 55:
                    continue
                lc = rc = None
                for k in (1, 2, 3):
                    if lc is None and tuple(px[x - k, y][:3]) in cloth_set:
                        lc = px[x - k, y]
                    if rc is None and tuple(px[x + k, y][:3]) in cloth_set:
                        rc = px[x + k, y]
                if lc and rc:
                    px[x, y] = (lc[0], lc[1], lc[2], 255)
    return im


def main():
    global HAIR, FLESH, GMIN, GMAX
    HAIR, FLESH = sample_bj()
    GMIN, GMAX = green_span()
    OUT.mkdir(parents=True, exist_ok=True)
    j = json.loads((ROOT / "docs" / "data"
                    / "sprite_copies.json").read_text())
    mut = [(c, n) for c, n in j["copies"] if n.startswith("MUT")]
    n = 0
    for var, rr in RAMPS.items():
        for ch, name in mut:
            if not (D / f"SPR{ch:03d}.png").exists():
                continue
            # MUTSA1 -> BJ1SA1 is too long for sprite naming; frames keep
            # the mutant's own frame letter + rotation: BJ<v><frame><rot>
            suffix = name[4:]           # e.g. "A1" from MUTSA1
            kind = name[3]              # S/W/A/D...
            convert(ch, rr).save(OUT / f"BJ{var}{kind}{suffix}.png")
            n += 1
    print(f"playersprite: {n} frames across {len(RAMPS)} variants")


if __name__ == "__main__":
    main()
