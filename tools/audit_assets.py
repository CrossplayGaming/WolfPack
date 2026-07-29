#!/usr/bin/env python3
"""Cross-game asset audit: verify what derived indices actually POINT AT.

The bug class this exists to catch: an index that resolves to a real
lump in both games but to the WRONG ART in one of them. Existence
checks cannot see it - WALL098 exists in Spear too, it is just a rock
face rather than a door - so this tool does two things existence checks
do not:

  1. Re-derives every data-layout-dependent constant from each game's
     own VSWAP manifest and reports them side by side. Anything the
     pipeline hardcodes must match the derived value for BOTH games.
  2. Renders a contact sheet per game of the assets those constants
     select (door pages, jambs, elevator, locked doors, the weapon
     psprites, the dead guard) so a human can confirm at a glance that
     a door looks like a door.

Run: python tools/audit_assets.py [--sheet]
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETS = ("wl6", "sod")


def manifest(setname):
    mf = ROOT / "build" / "vswap" / setname / "manifest.json"
    return json.loads(mf.read_text()) if mf.exists() else None


def derived(setname):
    """Constants the source computes from data layout, per build."""
    m = manifest(setname)
    if not m:
        return None
    spritestart = m["spritestart"]
    doorwall = spritestart - 8          # WL_DRAW.C:19
    return {
        "walls": m["walls"],
        "spritestart": spritestart,
        "soundstart": m["soundstart"],
        "DOORWALL": doorwall,
        "door normal": (doorwall, doorwall + 1),
        "door jamb": (doorwall + 2, doorwall + 3),
        "door elevator": (doorwall + 4, doorwall + 5),
        "door locked": (doorwall + 6, doorwall + 7),
    }


def check_enum(vals):
    """The parsed sprite enum must have exactly as many entries as the
    VSWAP has sprites. A single dropped name (id's header has one - a
    MACHINEGUNATK3 missing its SPR_ prefix) shifts every later index and
    silently mis-draws weapons in BOTH games. This is the independent
    cross-check: parsed length vs what the data actually contains."""
    sys.path.insert(0, str(ROOT / "tools"))
    from gen_enemies import sprite_enum
    bad = []
    for s in SETS:
        m = manifest(s)
        if not m:
            continue
        n = len(sprite_enum(spear=(s == "sod")))
        if n != m["sprites"]:
            bad.append(f"{s}: enum parsed {n} names, VSWAP has "
                       f"{m['sprites']} sprites - indices are shifted")
    return bad


def check_hardcodes():
    """No raw WALL### / SPR### literals in the pipeline. Every one is a
    latent per-game bug: the door pocket carried a hardcoded WALL100
    (WL6's jamb) that rendered as stone in Spear, on exactly one flank
    of every door. Derive from the data instead."""
    import re
    bad = []
    for f in ("convert_udmf.py", "make_assets.py"):
        src = (ROOT / "tools" / f).read_text(errors="replace")
        for n, line in enumerate(src.splitlines(), 1):
            code = line.split("#")[0]
            for m in re.findall(r'"(WALL\d{3}|SPR\d{3})"', code):
                if m == "WALL000":          # the void filler, game-agnostic
                    continue
                bad.append(f"{f}:{n} hardcodes {m}")
    return bad


def check_jambs():
    """Every wall face touching a door must carry the jamb page. Ground
    truth comes from the MAP DATA (walls adjacent to door tiles), not
    from our own emission - the pocket-side bug halved this silently."""
    import json as _j
    import re
    bad = []
    for s in SETS:
        lv = ROOT / "build" / "levels" / s / "MAP00.json"
        tm = ROOT / "build" / "udmf" / s / "MAP00.textmap"
        d = derived(s)
        if not (lv.exists() and tm.exists() and d):
            continue
        dec = _j.loads(lv.read_text())["decoded0"]
        doors = {(i % 64, i // 64) for i, c in enumerate(dec)
                 if c["kind"] == "door"}
        walls = {(i % 64, i // 64) for i, c in enumerate(dec)
                 if c["kind"] in ("wall", "elevator_switch", "exit_rail")}
        want = sum(1 for (x, y) in walls
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                   if (x + dx, y + dy) in doors)
        t = tm.read_text()
        dw = d["DOORWALL"]
        got = (len(re.findall("WALL%03d" % (dw + 2), t))
               + len(re.findall("WALL%03d" % (dw + 3), t))) // 3
        if got < want:
            bad.append(f"{s} MAP00: {got} jamb faces emitted, map data "
                       f"has {want} wall faces touching doors")
    return bad


# Palettes present in the data that we deliberately do NOT apply.
UNUSED_PALETTES = {"IDGUYSPALETTE"}     # the id-guys easter egg screen


def check_palettes():
    """Every *PALETTE chunk in a game's graphics enum must either be
    applied to a picture or be listed as deliberately unused. Spear's
    art is not all in the game palette: its title halves and nine
    ending screens carry their own, and decoding them against the game
    palette renders them like a photo negative (user repro on the title
    screen - the ending screens had already been handled, which is
    exactly how a hand-maintained list goes stale)."""
    import re
    sys.path.insert(0, str(ROOT / "tools"))
    from extract_vgagraph import parse_enum
    src = (ROOT / "tools" / "extract_vgagraph.py").read_text(errors="replace")
    applied = set(re.findall(r'"(\w+PALETTE)"', src))
    bad = []
    for header, tag in (("GFXV_WL6.H", "wl6"), ("GFXV_SOD.H", "sod")):
        try:
            names = parse_enum(header)
        except SystemExit:
            continue
        for v in names.values():
            if (v.endswith("PALETTE") and v not in applied
                    and v not in UNUSED_PALETTES):
                bad.append(f"{tag}: {v} exists in the data but no picture "
                           f"is repalettised with it")
    return bad


def check_pipeline(vals):
    """Compare what the converter would emit against the derived truth."""
    sys.path.insert(0, str(ROOT / "tools"))
    from convert_udmf import doorwall_for
    bad = []
    for s in SETS:
        if vals.get(s) is None:
            continue
        want = vals[s]["DOORWALL"]
        got = doorwall_for(s)
        if got != want:
            bad.append(f"{s}: converter DOORWALL={got}, data says {want}")
    return bad


def sheet():
    """Contact sheet: what each derived index actually looks like."""
    from PIL import Image
    out_dir = ROOT / "dist"
    out_dir.mkdir(exist_ok=True)
    rows = []
    for s in SETS:
        d = derived(s)
        if not d:
            continue
        wl = ROOT / "build" / "vswap" / s / "walls"
        picks = []
        for label, pair in (("normal", d["door normal"]),
                            ("jamb", d["door jamb"]),
                            ("elev", d["door elevator"]),
                            ("lock", d["door locked"])):
            for n in pair:
                f = wl / f"WALL{n:03d}.png"
                picks.append((f"{s} {label} {n}", f))
        # the weapon psprites, straight from the built assets
        adir = ROOT / "build" / ("assets_sod" if s == "sod" else "assets")
        for w in ("WKNFA0", "WPISA0", "WMGNA0", "WCHNA0", "SDEDA0"):
            picks.append((f"{s} {w}", adir / "sprites" / f"{w}.png"))
        rows.append(picks)
    if not rows:
        return
    cell, pad = 96, 4
    cols = max(len(r) for r in rows)
    img = Image.new("RGB", (cols * (cell + pad) + pad,
                            len(rows) * (cell + pad + 14) + pad), (24, 24, 24))
    from PIL import ImageDraw
    dr = ImageDraw.Draw(img)
    for ry, picks in enumerate(rows):
        y = pad + ry * (cell + pad + 14)
        for cx, (label, f) in enumerate(picks):
            x = pad + cx * (cell + pad)
            if f.exists():
                im = Image.open(f).convert("RGB").resize((cell, cell),
                                                         Image.NEAREST)
                img.paste(im, (x, y))
            dr.text((x, y + cell + 2), label.split(" ", 1)[1][:14],
                    fill=(200, 200, 200))
    p = out_dir / "asset_audit.png"
    img.save(p)
    print(f"contact sheet: {p}")


def main():
    vals = {s: derived(s) for s in SETS}
    keys = [k for k in (vals.get("wl6") or {}) if k]
    print(f"{'CONSTANT':16s} {'wl6':>18s} {'sod':>18s}   same?")
    for k in keys:
        a = vals["wl6"][k] if vals["wl6"] else "-"
        b = vals["sod"][k] if vals["sod"] else "-"
        print(f"{k:16s} {str(a):>18s} {str(b):>18s}   "
              f"{'yes' if a == b else 'NO (must be per-game)'}")
    print()
    bad = (check_enum(vals) + check_pipeline(vals)
           + check_hardcodes() + check_jambs() + check_palettes())
    if bad:
        print("PIPELINE MISMATCH:")
        for b in bad:
            print("  ", b)
        sys.exit(1)
    print("sprite enum length matches VSWAP sprite count (both games)")
    print("pipeline derived constants agree with both games' data")
    print("no hardcoded WALL/SPR indices in the pipeline")
    print("jamb faces match the map data in both games")
    print("every custom palette in the data is applied or acknowledged")
    if "--sheet" in sys.argv:
        sheet()


if __name__ == "__main__":
    main()
