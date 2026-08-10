#!/usr/bin/env python3
"""Enhanced-lighting assets: pool-less fixtures, brightmaps, GLDEFS.

Eric's observation drives the design: Wolf's hanging fixtures carry a
PAINTED pool of light on the floor - baked into the same sprite as the
fixture (the voxel lathe's run-splitter proved they are two disjoint
drawings on one canvas). With a real dynamic light attached, the fake
pool must go, or the room shows both. So per light-source sprite:

  1. If its painted rows form 2+ disjoint vertical runs, emit a frame-B
     lump with everything but the tallest run erased (fixture only).
     The lighting handler swaps fixtures to frame B while enhanced
     lighting is on; classic mode keeps the original painted pool.
  2. Emit a brightmap masking the sprite's bright pixels, so fixtures
     keep glowing when depth shading dims the room.
  3. Emit GLDEFS (src/GLDEFS.gen + .spear overlay): pointlight defs and
     object attachments for the fixtures and boss projectiles, plus the
     brightmap bindings, plus wolfdata/lighting.txt naming the classes
     whose fixtures have a frame B (the handler's swap list - shipped
     data, not a hardcoded zscript list that would go stale).

Runs from build.py after make_assets (writes INTO build/assets*).
"""
import pathlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GAP_TOL = 2

# (class prefix, statinfo index, light name, rgb 0-1, size, up-offset)
FIXTURES = [
    ("Static03", 3,  "WLAMP",  (1.0, 0.85, 0.55), 84,  40),
    ("Static04", 4,  "WCHAND", (1.0, 0.85, 0.55), 128, 52),
    ("Static14", 14, "WCEIL",  (0.85, 1.0, 0.85), 112, 56),
    ("Static42", 42, "WRED",   (1.0, 0.25, 0.2),  96,  48),   # wl6 only
]
# (class, sprite, light name, rgb, size) - sprite names from the
# States blocks in bosses.zs / sod.zs
PROJECTILES = [
    ("WolfRocket",     "MISL", "WROCK",  (1.0, 0.6, 0.25), 64),
    ("WolfFire",       "FIRE", "WFIRE",  (1.0, 0.55, 0.2), 56),
    ("WolfNeedle",     "HYPO", "WNEED",  (0.45, 1.0, 0.45), 36),
    ("WolfHeatSeeker", "HMIS", "WROCK",  None, 0),
    ("WolfSpark",      "SPRK", "WSPARK", (1.0, 0.5, 0.15), 48),
]


def runs_of(im):
    tr = im.info.get("transparency")
    px = im.load()
    w, h = im.size
    rows = [y for y in range(h) if any(px[x, y] != tr for x in range(w))]
    if not rows:
        return [], tr
    out, cur = [], [rows[0]]
    for a, b in zip(rows, rows[1:]):
        if b - a <= GAP_TOL + 1:
            cur.append(b)
        else:
            out.append(cur)
            cur = [b]
    out.append(cur)
    return out, tr


def fixture_variant(src, dst):
    """Pool-less lump: tallest run only. Returns True if a pool existed.

    The output is REBUILT as a clean mode-P image with single-index
    transparency (index 255) rather than re-saving the source object:
    passing the source's transparency blob through PIL produced PNGs
    the engine silently refused to install as sprite frames - proven
    by A/B: byte-copied originals rendered, these did not."""
    im = Image.open(src)
    runs, tr = runs_of(im)
    if len(runs) < 2:
        return False
    best = max(runs, key=len)
    keep = set(y for y in best)
    px = im.load()
    out = Image.new("P", im.size, 255)
    out.putpalette(im.getpalette())
    op = out.load()
    for y in range(im.height):
        if y not in keep:
            continue
        for x in range(im.width):
            c = px[x, y]
            if c != tr:
                op[x, y] = c
    out.save(dst, transparency=255)
    # splice the SOURCE's grAb chunk (sprite origin offsets) into the
    # output: PIL strips unknown chunks, and without grAb the sprite
    # draws displaced out of view - the true cause of every "invisible
    # fixture" in this feature's history (registration and transparency
    # were both red herrings; the byte-copied original rendered because
    # it kept its offsets).
    src_bytes = pathlib.Path(src).read_bytes()
    i = src_bytes.find(b"grAb")
    if i >= 8:
        chunk = src_bytes[i - 4:i + 4 + 8 + 4]   # len + tag + 8 data + crc
        d = pathlib.Path(dst).read_bytes()
        ihdr_end = d.find(b"IHDR") + 4 + 13 + 4
        pathlib.Path(dst).write_bytes(
            d[:ihdr_end] + chunk + d[ihdr_end:])
    return True


def brightmap(src, dst, pal):
    """White where the sprite is bright/saturated - those pixels ignore
    sector darkness (the lamp glass keeps glowing in a dim room)."""
    im = Image.open(src)
    tr = im.info.get("transparency")
    px = im.load()
    out = Image.new("RGB", im.size, (0, 0, 0))
    op = out.load()
    n = 0
    for y in range(im.height):
        for x in range(im.width):
            c = px[x, y]
            if c == tr:
                continue
            r, g, b = pal[c]
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            sat = max(r, g, b) - min(r, g, b)
            if lum > 150 or (sat > 120 and max(r, g, b) > 160):
                op[x, y] = (255, 255, 255)
                n += 1
    if n == 0:
        return False
    out.save(dst)
    return True


def gen_for_set(setname):
    import json
    assets = ROOT / "build" / ("assets_sod" if setname == "sod"
                               else "assets")
    spr = assets / "sprites"
    bm = assets / "brightmaps"
    bm.mkdir(exist_ok=True)
    pal = json.loads((ROOT / "build/vswap/palette.json").read_text())
    prefix = "D" if setname == "sod" else "S"
    cls = "Sod" if setname == "sod" else "Wolf"

    lights, objects, bmaps, swap = [], [], [], []
    for stem, idx, lname, rgb, size, up in FIXTURES:
        if setname == "sod" and idx == 42:
            continue                     # red light is wl6-only
        a = spr / f"{prefix}{idx:03d}A0.png"
        if not a.exists():
            continue
        # pool-less variant under its OWN sprite name (XPnn): swapping
        # frames of the same sprite rendered invisible even with the
        # lump valid - frame B of an A-only States block never enters
        # the sprite def. A separate name registered by a dormant
        # States block (lighting.zs) is the playbook-proof path. Same
        # name in both sets so one registration class serves both.
        bname = f"XP{idx:02d}A0.png"
        if fixture_variant(a, spr / bname):
            swap.append(f"{cls}{stem} XP{idx:02d}")
        for lump in (f"{prefix}{idx:03d}A0", f"XP{idx:02d}A0"):
            f = spr / f"{lump}.png"
            if f.exists() and brightmap(f, bm / f"{lump}.png", pal):
                bmaps.append(lump)
        if rgb:
            lights.append((lname, rgb, size, up))
        objects.append((f"{cls}{stem}", f"{prefix}{idx:03d}", lname))

    # GLDEFS gets the BRIGHTMAPS only. Attaching a light to a frame
    # here binds it to the sprite forever: the lamps and projectiles
    # glowed with enhanced lighting switched off, because nothing about
    # a GLDEFS attachment can be conditional (user report: "some
    # dynamic light setting stuck on"). The lights are now DATA, read
    # by lighting.zs, which attaches them when the option is on and
    # removes them when it is off.
    gl = ["// GENERATED by tools/gen_lighting.py - do not edit"]
    lightrows = []
    for cname, sprname, lname in objects:
        for st, idx, ln, rgb, size, up in FIXTURES:
            if cname.endswith(st):
                lightrows.append(f"{cname} {int(rgb[0] * 255)} "
                                 f"{int(rgb[1] * 255)} {int(rgb[2] * 255)} "
                                 f"{size} {up}")
                break
    for cname, sprname, lname, rgb, size in PROJECTILES:
        if not rgb:
            # HeatSeeker borrows the rocket's light
            for c2, s2, l2, r2, z2 in PROJECTILES:
                if l2 == lname and r2:
                    rgb, size = r2, z2
                    break
        if rgb:
            lightrows.append(f"{cname} {int(rgb[0] * 255)} "
                             f"{int(rgb[1] * 255)} {int(rgb[2] * 255)} "
                             f"{size} 0")
    for lump in bmaps:
        gl.append(f'brightmap sprite "{lump}"\n{{\n'
                  f'    map "brightmaps/{lump}.png"\n}}')

    # a root file named gldefs.txt becomes the GLDEFS lump automatically
    (assets / "gldefs.txt").write_text("\n\n".join(gl) + "\n")
    (assets / "wolfdata" / "lighting.txt").write_text(
        "\n".join(swap) + "\n")
    (assets / "wolfdata" / "lights.txt").write_text(
        "\n".join(lightrows) + "\n")
    print(f"{setname}: {len(swap)} pool swaps, {len(bmaps)} brightmaps, "
          f"{len(lightrows)} attachable lights")


def main():
    for s in ("wl6", "sod"):
        if (ROOT / "build" / ("assets_sod" if s == "sod"
                              else "assets")).is_dir():
            gen_for_set(s)


if __name__ == "__main__":
    main()
