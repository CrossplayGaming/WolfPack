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


def sibling_check(table):
    """No pair may reuse the keyed wall's own light/dark textures -
    Eric's rule after the v1 review: WALL015 under the blue cells read
    as the wall folding onto the ceiling. Loud failure, not a warning."""
    bad = []
    for code, pair in table.items():
        if code == "fallback":
            continue
        c = int(code)
        sibs = {f"WALL{(c - 1) * 2:03d}", f"WALL{(c - 1) * 2 + 1:03d}"}
        for tex in pair:
            if tex in sibs:
                bad.append(f"code {code}: {tex} is that wall's own face")
    if bad:
        raise SystemExit("flat_pairs sibling violations:\n  "
                         + "\n  ".join(bad))


def door_lines(dec, area_pair, pushwalls):
    """Doors AND pushwall tiles get a neighboring area's pair - the
    next room's texture runs under them instead of bare grey (Eric's
    screenshots: a revealed secret pocket showed naked flats mid-
    corridor; pushwall tiles are walls in the map data, so the area
    pass never reaches their dedicated sectors). Deterministic pick:
    north/west neighbor first."""
    out = []
    tiles = [(i % 64, i // 64) for i, t in enumerate(dec)
             if t["kind"] == "door"]
    tiles += pushwalls
    for x, y in tiles:
        for dx, dy in ((0, -1), (-1, 0), (0, 1), (1, 0)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < 64 and 0 <= ny < 64):
                continue
            n = dec[ny * 64 + nx]
            if (n["kind"] in ("floor", "ambush_floor")
                    and n.get("area", -1) in area_pair):
                c, f = area_pair[n["area"]]
                out.append(f"T {x} {y} {c} {f}")
                break
    return out


def main():
    total = 0
    for setname in ("wl6", "sod"):
        table = PAIRS.get(setname) or {}
        if not table:
            print(f"{setname}: no pair table - skipped")
            continue
        sibling_check(table)
        fallback = table["fallback"]
        lv = ROOT / "build" / "levels" / setname
        out = ROOT / "build" / "udmf" / setname
        if not lv.is_dir():
            continue
        for f in sorted(lv.glob("MAP*.json")):
            d = json.loads(f.read_text())
            per = area_walls(d["decoded0"])
            lines = []
            area_pair = {}
            for a in sorted(per):
                c = per[a]
                if sum(c.values()) >= 8:
                    dom = str(c.most_common(1)[0][0])
                    ceil, floor = table.get(dom, fallback)
                else:
                    ceil, floor = fallback
                area_pair[a] = (ceil, floor)
                lines.append(f"{chr(65 + a)} {ceil} {floor}")
            pw = [(o["x"], o["y"]) for o in d["objects"]
                  if o["kind"] == "pushwall"]
            lines += door_lines(d["decoded0"], area_pair, pw)
            (out / f"{f.stem}.flats.txt").write_text("\n".join(lines) + "\n")
            total += 1
    print(f"flat assignments written for {total} maps")


if __name__ == "__main__":
    main()
