#!/usr/bin/env python3
"""Import the user's AI-painted BJ sheets into the player sprite set.

import/bj_sheet.png follows the guard reference layout (stand 8, walk
4x8, pain 2 + shoot 3, die 3 + corpse); import/bj_attack_sheet.png adds
8 ROTATED firing frames - a deliberate extension beyond the original 49
(a player's shots must read from any angle; enemies always face their
target so the original never needed it).

Pipeline per cell: largest non-background blob (drops the sheet's
labels), scale-matched to the guard's world height, bottom-anchored on
a 64x64 canvas, quantized to the Wolf palette, background keyed to
alpha. Clothing variants 2-4 (blue/red/tan) are recolored from the
extracted grey via palette-ramp remap. Output: build/playersprite/BJ*.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image
from wolf_common import ROOT, load_palette

IMP = ROOT / "import"
OUT = ROOT / "build" / "playersprite"
pal = load_palette()


def lum(rgb):
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]


def key_of(im):
    px = im.convert("RGB").load()
    return px[2, 2]


def isbg(p, key, tol=45):
    return (abs(p[0] - key[0]) + abs(p[1] - key[1])
            + abs(p[2] - key[2])) < tol


def bands(im, key):
    """rows of the sheet that contain foreground, merged into bands"""
    px = im.convert("RGB").load()
    rows = []
    for y in range(im.height):
        n = 0
        for x in range(0, im.width, 3):
            if not isbg(px[x, y], key):
                n += 1
        rows.append(n > 3)
    out, start = [], None
    for y, on in enumerate(rows):
        if on and start is None:
            start = y
        elif not on and start is not None:
            out.append((start, y))
            start = None
    if start is not None:
        out.append((start, im.height))
    return [b for b in out if b[1] - b[0] > 40]      # drop label-only bands


def cells(im, key, band):
    """column runs of foreground within a band"""
    px = im.convert("RGB").load()
    y0, y1 = band
    cols = []
    for x in range(im.width):
        n = 0
        for y in range(y0, y1, 2):
            if not isbg(px[x, y], key):
                n += 1
        cols.append(n > 1)
    out, start = [], None
    for x, on in enumerate(cols):
        if on and start is None:
            start = x
        elif not on and start is not None:
            out.append((start, x))
            start = None
    if start is not None:
        out.append((start, im.width))
    return [(x0, y0, x1, y1) for x0, x1 in out if x1 - x0 > 20]


def largest_blob(im, key):
    """bbox of the largest 4-connected foreground component (drops text)"""
    px = im.convert("RGB").load()
    w, h = im.size
    seen = [[False] * h for _ in range(w)]
    best, bestn = None, 0
    for sx in range(w):
        for sy in range(h):
            if seen[sx][sy] or isbg(px[sx, sy], key):
                continue
            stack = [(sx, sy)]
            seen[sx][sy] = True
            minx, miny, maxx, maxy, n = sx, sy, sx, sy, 0
            while stack:
                x, y = stack.pop()
                n += 1
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if (0 <= nx < w and 0 <= ny < h and not seen[nx][ny]
                            and not isbg(px[nx, ny], key)):
                        seen[nx][ny] = True
                        stack.append((nx, ny))
            if n > bestn:
                bestn, best = n, (minx, miny, maxx + 1, maxy + 1)
    return best


# quantization to the Wolf palette (cached by color)
_qcache = {}


def quant(p):
    if p in _qcache:
        return _qcache[p]
    best, bd = 0, 1 << 30
    for i in range(256):
        r, g, b = pal[i]
        d = (r - p[0]) ** 2 + (g - p[1]) ** 2 + (b - p[2]) ** 2
        if d < bd:
            bd, best = d, i
    _qcache[p] = best
    return best


def to_frame(cell_im, key, scale):
    """blob -> scaled, bottom-anchored, palette-quantized 64x64 RGBA"""
    bb = largest_blob(cell_im, key)
    if bb is None:
        return None
    art = cell_im.crop(bb)
    nw = max(1, round(art.width * scale))
    nh = max(1, round(art.height * scale))
    art = art.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ox = (64 - nw) // 2
    oy = 64 - nh                     # feet on the canvas floor
    spx = art.convert("RGB").load()
    opx = out.load()
    near = [[False] * nh for _ in range(nw)]
    for y in range(nh):
        for x in range(nw):
            p = spx[x, y]
            if isbg(p, key, 60):
                continue
            near[x][y] = isbg(p, key, 130)   # bg-tinted halo pixel
            q = pal[quant(p)]
            if 0 <= ox + x < 64 and 0 <= oy + y < 64:
                opx[ox + x, oy + y] = (q[0], q[1], q[2], 255)
    # two erode passes: halo pixels adjacent to transparency drop
    for _ in range(2):
        drop = []
        for y in range(nh):
            for x in range(nw):
                if not near[x][y]:
                    continue
                cx, cy = ox + x, oy + y
                if not (0 <= cx < 64 and 0 <= cy < 64):
                    continue
                if opx[cx, cy][3] == 0:
                    continue
                for dx, dy in ((1,0), (-1,0), (0,1), (0,-1)):
                    tx, ty = cx + dx, cy + dy
                    if not (0 <= tx < 64 and 0 <= ty < 64)                             or opx[tx, ty][3] == 0:
                        drop.append((cx, cy))
                        break
        for cx, cy in drop:
            opx[cx, cy] = (0, 0, 0, 0)
    return out


# clothing variants: remap the grey ramp of the imported art
def ramp(lo, hi):
    return sorted(range(lo, hi), key=lambda i: lum(pal[i]))


GREY = ramp(0x10, 0x20)
VARIANTS = {"2": ramp(0x98, 0xA0), "3": ramp(0x24, 0x2C),
            "4": ramp(0xD4, 0xDC)}


def recolor(frame, target, protect=None):
    """Uniform grey -> variant colour, v2.

    v1 remapped only EXACT ramp-index colours and had no notion of
    where the face is. Both defects shipped in the skin: near-greys
    that quantized off the 0x10-0x20 ramp stayed grey (speckled
    uniforms on every variant), and the eye whites - grey by any
    measure - recolored into a blue/red patch across the face.

    v2 classifies by measurement: a pixel is uniform-grey if its
    channels are close (desaturated) and its luminance sits in the
    grey ramp's band; it maps onto the target ramp at the same
    relative brightness. Face detail is protected by WARM ADJACENCY,
    not geometry: a grey pixel touching skin/hair tones (eye whites,
    face shading) is face, wherever it sits - which also covers lying
    death frames, where a "head zone" row band points sideways. A
    geometric zone was tried first and left a grey yoke across the
    shoulders. Boots (saturated navy) and gun darks (below the band)
    never qualify. `protect` is an optional set of (x, y) the caller
    knows better about (import_bj_gun passes the machine-gun mask,
    classified at source resolution where metal and fabric separate
    cleanly - at 64x64 their luminances are one smeared mass).
    """
    im = frame.copy()
    px = im.load()
    lo = min(lum(pal[i]) for i in GREY) - 8
    hi = max(lum(pal[i]) for i in GREY) + 8

    # Warmth is judged on a FROZEN snapshot of the input. Reading the
    # image being mutated protected the neighbours of every freshly
    # painted red/tan pixel (recolored warm counts as warm) and
    # checkerboarded those variants.
    src = frame.load()

    def warm(x, y):
        if not (0 <= x < 64 and 0 <= y < 64):
            return False
        r, g, b, a = src[x, y]
        return a and r > b + 40 and r > 110

    for y in range(64):
        for x in range(64):
            r, g, b, a = px[x, y]
            if not a:
                continue
            if protect and (x, y) in protect:
                continue
            if any(warm(x + dx, y + dy)
                   for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                   if (dx, dy) != (0, 0)):
                continue
            if max(r, g, b) - min(r, g, b) >= 30:
                continue                        # saturated: skin, boots
            v = lum((r, g, b))
            if not (lo <= v <= hi):
                continue                        # gun darks, highlights
            t = target[min(len(target) - 1,
                           int((v - lo) / max(1e-6, hi - lo)
                               * len(target)))]
            q = pal[t]
            px[x, y] = (q[0], q[1], q[2], a)
    return im


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    main_sheet = Image.open(IMP / "bj_sheet.png").convert("RGB")
    atk_sheet = Image.open(IMP / "bj_attack_sheet.png").convert("RGB")
    k1, k2 = key_of(main_sheet), key_of(atk_sheet)

    b1 = bands(main_sheet, k1)
    expect = [8, 8, 8, 8, 8, 5, 4]
    rows = []
    for band in b1:
        cs = cells(main_sheet, k1, band)
        rows.append(cs)
    counts = [len(r) for r in rows]
    print("main sheet bands:", counts, "(expect", expect, ")")

    # world scale: guard stand rot1 art height vs imported stand rot1
    guard = Image.open(ROOT / "build" / "vswap" / "wl6" / "sprites"
                       / "SPR050.png").convert("RGBA")
    gh = guard.split()[3].getbbox()
    gheight = gh[3] - gh[1]
    stand1 = largest_blob(main_sheet.crop(rows[0][0]), k1)
    sheight = stand1[3] - stand1[1]
    scale = gheight / sheight
    print(f"scale {scale:.3f} (guard {gheight}px / import {sheight}px)")

    names = []
    for i in range(8):
        names.append((0, i, f"BJ1SA{i+1}"))
    for f, letter in enumerate("ABCD"):
        for i in range(8):
            names.append((1 + f, i, f"BJ1W{letter}{i+1}"))
    names += [(5, 0, "BJ1PA0"), (5, 1, "BJ1PB0"),
              (5, 2, "BJ1AA0"), (5, 3, "BJ1AB0"), (5, 4, "BJ1AC0"),
              (6, 0, "BJ1DA0"), (6, 1, "BJ1DB0"), (6, 2, "BJ1DC0"),
              (6, 3, "BJ1DD0")]

    frames = {}
    for row, col, name in names:
        if row >= len(rows) or col >= len(rows[row]):
            print("MISSING cell for", name)
            continue
        fr = to_frame(main_sheet.crop(rows[row][col]), k1, scale)
        if fr:
            frames[name] = fr

    # attack sheet: 2 bands x 4 = fire rotations 1-8 (reading order).
    # Its art is drawn at a different size - compute its own scale from
    # the first cell's blob height.
    b2 = bands(atk_sheet, k2)
    first = cells(atk_sheet, k2, b2[0])[0]
    fb = largest_blob(atk_sheet.crop(first), k2)
    scale2 = gheight / (fb[3] - fb[1])
    print(f"attack scale {scale2:.3f}")
    # The sheet's reading order circles OPPOSITE to the engine's rotation
    # convention: keeping 1 (front) and 5 (back), 2-8 reverse. User repro
    # on the 2-window test: left and right firing views were mirrored.
    MIRROR = {1: 1, 2: 8, 3: 7, 4: 6, 5: 5, 6: 4, 7: 3, 8: 2}
    rot = 1
    for band in b2:
        for c in cells(atk_sheet, k2, band):
            fr = to_frame(atk_sheet.crop(c), k2, scale2)
            if fr and rot <= 8:
                frames[f"BJ1FA{MIRROR[rot]}"] = fr
                rot += 1
    print(f"fire rotations: {rot - 1}")

    # write variant 1 + recolors
    n = 0
    for name, fr in frames.items():
        fr.save(OUT / f"{name}.png")
        n += 1
        for v, target in VARIANTS.items():
            recolor(fr, target).save(OUT / f"BJ{v}{name[3:]}.png")
            n += 1
    print(f"imported {n} frames")

    # verification sheet
    S = 3
    per = 64 * S + 8
    keys = sorted(frames.keys())
    cols_n = 8
    rows_n = (len(keys) + cols_n - 1) // cols_n
    from PIL import ImageDraw
    sheet = Image.new("RGB", (cols_n * per + 8, rows_n * (per + 14) + 8),
                      (30, 30, 30))
    dr = ImageDraw.Draw(sheet)
    for i, kn in enumerate(keys):
        x = 8 + (i % cols_n) * per
        y = 8 + (i // cols_n) * (per + 14)
        u = frames[kn].resize((64 * S, 64 * S), Image.NEAREST)
        sheet.paste(u, (x, y), u)
        dr.text((x, y + 64 * S), kn, fill=(255, 247, 0))
    # dist/ does not exist yet on a fresh clone (build.py creates it
    # later) - the verification sheet must not be the crash
    (ROOT / "dist").mkdir(exist_ok=True)
    sheet.save(ROOT / "dist" / "bj_import_check.png")
    print("check sheet written")


if __name__ == "__main__":
    main()
