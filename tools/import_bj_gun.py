#!/usr/bin/env python3
"""Import Eric's redrawn BJ frames (set-at-a-time) over the MP skin.

Eric's second-pass workflow for the multiplayer BJ sprites: redraw the
frames in sets (one viewing angle at a time, gun in hand), drop them in
import/, and this tool swaps each set into the exact slots it belongs -
analysed, not assumed - across all four clothing variants.

FILENAME CONVENTION (one file per frame)
    BJ with gun <n>.png              walk frame n, FRONT view (rot 1)
    BJ with gun <n> <angle>.png      future sets; angle in ROT_WORDS

FRAME MAPPING - why identity
The four gun frames are 1:1 redraws of the original SPR_BJ_W1..W4
victory-run cycle. The painted skin's walk A-D follows the same gait
alternation (stride widths: originals 23,30,25,28 = narrow/wide/
narrow/wide; skin 20,23,19,23 = same), so gun n maps to skin frame
letter n: A,B,C,D. Silhouette IoU was tried first and could NOT
discriminate phases (all frames match everything at ~0.7) - stride
width is the discriminating measurement.

GEOMETRY - why the skin's, not the originals'
The originals stand 49px; the skin is guard-height-matched at 46-47px,
bottom-anchored. A frame converted at original geometry would make BJ
visibly grow whenever he faces the camera. Each new frame is therefore
scaled to the CURRENT skin frame it replaces (blob height -> blob
height) and bottom-anchored on the canvas floor exactly like
import_bj_sheet.to_frame does.

Output: build/playersprite/BJ{1-4}W{A-D}<rot>.png (grey + 3 recolors).
Run AFTER import_bj_sheet.py (play.bat/SETUP.bat do this).
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image

import import_bj_sheet as sheet                     # noqa: E402
from wolf_common import ROOT                        # noqa: E402

IMP = ROOT / "import"
OUT = ROOT / "build" / "playersprite"

# Viewing angle -> ZDoom rotation digit, as measured on the guard set
# (rot 1 = facing the viewer, 3/7 = profiles, 5 = back). Extend as
# Eric's sets arrive; a filename with no angle word is the front set.
ROT_WORDS = {
    "": "1",
    "back": "5",
    "left": "3",  "left profile": "3", "profile left": "3",
    "right": "7", "right profile": "7", "profile right": "7",
}

FRAME_LETTER = {1: "A", 2: "B", 3: "C", 4: "D"}


def key_out(im):
    """Alpha + magenta-family background -> transparent. Eric's frames
    arrive with mixed background (partly keyed, partly magenta)."""
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 128 or (r > 140 and b > 140 and g < 110):
                px[x, y] = (0, 0, 0, 0)
    return im


def blob_bbox_rgba(im):
    """bbox of visible art (alpha-keyed image)."""
    return im.getbbox()


def skin_metrics(letter, rot):
    """Height and bottom row of the current skin frame being replaced."""
    p = OUT / f"BJ1W{letter}{rot}.png"
    im = Image.open(p).convert("RGBA")
    px = im.load()
    ys = [y for y in range(64) for x in range(64) if px[x, y][3] >= 128]
    xs = [x for y in range(64) for x in range(64) if px[x, y][3] >= 128]
    return (max(ys) - min(ys) + 1, max(ys),
            (min(xs) + max(xs)) // 2)


def convert(src_path, letter, rot):
    art = key_out(Image.open(src_path))
    bb = art.getbbox()
    if bb is None:
        raise SystemExit(f"{src_path}: nothing visible after keying")
    art = art.crop(bb)

    want_h, want_bottom, want_cx = skin_metrics(letter, rot)
    scale = want_h / art.height
    nw = max(1, round(art.width * scale))
    art = art.resize((nw, want_h), Image.BOX)

    out = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    ox = max(0, min(64 - nw, want_cx - nw // 2))
    oy = want_bottom - want_h + 1
    spx = art.load()
    opx = out.load()
    for y in range(want_h):
        for x in range(nw):
            r, g, b, a = spx[x, y]
            if a < 128:
                continue
            q = sheet.pal[sheet.quant((r, g, b))]
            if 0 <= ox + x < 64 and 0 <= oy + y < 64:
                opx[ox + x, oy + y] = (q[0], q[1], q[2], 255)
    return out


def main():
    if not OUT.is_dir():
        raise SystemExit("build/playersprite missing - run "
                         "tools/import_bj_sheet.py first")
    pat = re.compile(r"^BJ with gun (\d)\s*(.*)\.png$", re.I)
    done = 0
    for f in sorted(IMP.glob("BJ with gun *.png")):
        m = pat.match(f.name)
        if not m:
            print(f"  skip {f.name}: name not understood")
            continue
        n = int(m.group(1))
        angle = m.group(2).strip().lower()
        if n not in FRAME_LETTER or angle not in ROT_WORDS:
            print(f"  skip {f.name}: frame {n} / angle '{angle}' unknown")
            continue
        letter, rot = FRAME_LETTER[n], ROT_WORDS[angle]
        frame = convert(f, letter, rot)
        frame.save(OUT / f"BJ1W{letter}{rot}.png")
        # The gun recolors with the uniform, as the painted skin's fire
        # frames always have. Separating it was tried and measured off
        # the table: gun and fabric luminance form one mass even at
        # source resolution - any threshold splits the uniform instead.
        for v, target in sheet.VARIANTS.items():
            sheet.recolor(frame, target).save(
                OUT / f"BJ{v}W{letter}{rot}.png")
        print(f"  {f.name} -> BJ*W{letter}{rot} (grey + 3 variants)")
        done += 1
    if not done:
        print("no 'BJ with gun' frames found in import/")
    else:
        print(f"{done} frames imported; rerun make_assets + build")


if __name__ == "__main__":
    main()
