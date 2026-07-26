#!/usr/bin/env python3
"""Phase 1: extract all Wolf3D / Spear levels to JSON.

MAPHEAD.WL6 + GAMEMAPS.WL6 (and .SOD) -> build/levels/<set>/MAPnn.json with:
  - width/height (asserted 64x64 per WL_GAME.C:656), name, rlew tag
  - plane0: raw walls grid + semantic decode (wall/door/area/ambush)
  - plane1: object list with charter semantics (spawns, statics, turns, pushwalls)

Unknown plane-1 codes are collected and FAIL the run (handoff rule: the
pipeline asserts it consumed every code or fails loudly — no silent drops).
Outputs under build/ (gitignored); nothing extracted is ever committed.
"""
import json
import struct
import sys
from pathlib import Path

from wolf_common import (ROOT, find_data, load_maphead, carmack_expand,
                         rlew_expand, wall_meaning, object_meaning)

OUT = ROOT / "build" / "levels"


def load_plane(maps, pstart, plen, rlew, ntiles):
    seg = maps[pstart:pstart + plen]
    (carmack_words,) = struct.unpack_from("<H", seg, 0)
    words = carmack_expand(seg[2:], carmack_words // 2)
    return rlew_expand(words[1:], rlew, ntiles)


def extract_set(setname, maphead_path, gamemaps_path):
    sod = setname == "sod"
    out = OUT / setname
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.json"):
        f.unlink()

    rlew, offsets = load_maphead(maphead_path)
    maps = gamemaps_path.read_bytes()
    present = [(i, o) for i, o in enumerate(offsets) if o > 0]

    unknowns = {}
    summary = []
    for mapnum, off in present:
        planestart = struct.unpack_from("<3i", maps, off)
        planelen = struct.unpack_from("<3H", maps, off + 12)
        width, height = struct.unpack_from("<2H", maps, off + 18)
        name = maps[off + 22:off + 38].split(b"\x00")[0].decode("latin1")
        assert (width, height) == (64, 64), f"map {mapnum} not 64x64"
        n = width * height

        plane0 = load_plane(maps, planestart[0], planelen[0], rlew, n)
        plane1 = load_plane(maps, planestart[1], planelen[1], rlew, n)

        decoded0 = [wall_meaning(v) for v in plane0]
        objects = []
        for idx, v in enumerate(plane1):
            m = object_meaning(v, sod)
            if m is None:
                continue
            if m["kind"] == "unknown":
                unknowns.setdefault(v, []).append((mapnum, idx % 64, idx // 64))
                continue
            m = dict(m)
            m.update(x=idx % 64, y=idx // 64, code=v)
            objects.append(m)

        doors = sum(1 for m in decoded0 if m["kind"] == "door")
        pushwalls = sum(1 for o in objects if o["kind"] == "pushwall")
        enemies = sum(1 for o in objects if o["kind"] in ("enemy", "boss", "ghost"))
        starts = [o for o in objects if o["kind"] == "player_start"]
        assert len(starts) == 1, f"map {mapnum}: {len(starts)} player starts"

        (out / f"MAP{mapnum:02d}.json").write_text(json.dumps({
            "set": setname, "map": mapnum, "name": name,
            "width": width, "height": height, "rlew_tag": rlew,
            "plane0": plane0, "decoded0": decoded0, "objects": objects,
        }))
        summary.append(f"  MAP{mapnum:02d} '{name}': {doors} doors, "
                       f"{pushwalls} pushwalls, {enemies} enemies, "
                       f"start dir {starts[0]['dir']}")

    print(f"{setname}: extracted {len(present)} maps -> {out}")
    for s in summary:
        print(s)
    return unknowns


def main():
    mapheads = find_data("WL6") | find_data("SOD")
    sets = []
    wl6 = find_data("WL6")
    sod = find_data("SOD")
    if "MAPHEAD" in wl6 and "GAMEMAPS" in wl6:
        sets.append(("wl6", wl6["MAPHEAD"], wl6["GAMEMAPS"]))
    if "MAPHEAD" in sod and "GAMEMAPS" in sod:
        sets.append(("sod", sod["MAPHEAD"], sod["GAMEMAPS"]))
    if not sets:
        sys.exit("no MAPHEAD/GAMEMAPS found in gamedata/ or Steam install")

    all_unknowns = {}
    for setname, mh, gm in sets:
        u = extract_set(setname, mh, gm)
        for code, spots in u.items():
            all_unknowns.setdefault((setname, code), []).extend(spots)

    if all_unknowns:
        print("\nFATAL: unknown plane-1 codes (charter gap — resolve, never drop):")
        for (setname, code), spots in sorted(all_unknowns.items()):
            print(f"  {setname} code {code}: {len(spots)}x, first at "
                  f"map {spots[0][0]} ({spots[0][1]},{spots[0][2]})")
        sys.exit(1)
    print("\nall plane-1 codes consumed; no unknowns")


if __name__ == "__main__":
    main()
