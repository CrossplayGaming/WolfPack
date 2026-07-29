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
    bad = check_pipeline(vals)
    if bad:
        print("PIPELINE MISMATCH:")
        for b in bad:
            print("  ", b)
        sys.exit(1)
    print("pipeline derived constants agree with both games' data")
    if "--sheet" in sys.argv:
        sheet()


if __name__ == "__main__":
    main()
