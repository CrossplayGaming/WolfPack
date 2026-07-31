#!/usr/bin/env python3
"""Per-area flat assignments for the textured floors/ceilings toggle.

For every map: find each area's DOMINANT wall (wall faces adjacent to
the area's floor tiles - a face count, so a decorative one-off banner
cannot claim a room), look it up in docs/data/flat_pairs.json, and emit
one sidecar lump per map:

    build/udmf/<set>/MAPxx.flats.txt      (packed as wolfdata/MAPNN.flats)

        A WALL042 WALL023
        B WALL015 WALL003
        ...

Line format: area letter ('A' + area number, matching the grid lump's
area section), ceiling texture, floor texture. Sub-8-face areas
(closets) inherit the fallback pair. Runtime application lives in
zscript/flats.zs; the toggle is wolf_mod_flats in the Modernization
menu. Sets with an empty table (sod, for now) get no sidecars and the
toggle no-ops there.

Run after convert_udmf; make_assets packs the sidecars.
"""
import collections
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAIRS = json.loads((ROOT / "docs/data/flat_pairs.json").read_text())


def area_walls(dec):
    """area -> Counter of adjacent wall codes (face count)."""
    per = collections.defaultdict(collections.Counter)
    for i, t in enumerate(dec):
        if t["kind"] not in ("floor", "ambush_floor"):
            continue
        x, y = i % 64, i // 64
        a = t.get("area", -1)
        if a < 0:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < 64 and 0 <= ny < 64:
                n = dec[ny * 64 + nx]
                if n["kind"] == "wall":
                    per[a][n["code"]] += 1
    return per


def main():
    total = 0
    for setname in ("wl6", "sod"):
        table = PAIRS.get(setname) or {}
        if not table:
            print(f"{setname}: no pair table - skipped")
            continue
        fallback = table["fallback"]
        lv = ROOT / "build" / "levels" / setname
        out = ROOT / "build" / "udmf" / setname
        if not lv.is_dir():
            continue
        for f in sorted(lv.glob("MAP*.json")):
            d = json.loads(f.read_text())
            per = area_walls(d["decoded0"])
            lines = []
            for a in sorted(per):
                c = per[a]
                if sum(c.values()) >= 8:
                    dom = str(c.most_common(1)[0][0])
                    ceil, floor = table.get(dom, fallback)
                else:
                    ceil, floor = fallback
                lines.append(f"{chr(65 + a)} {ceil} {floor}")
            (out / f"{f.stem}.flats.txt").write_text("\n".join(lines) + "\n")
            total += 1
    print(f"flat assignments written for {total} maps")


if __name__ == "__main__":
    main()
