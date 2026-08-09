#!/usr/bin/env python3
"""Build the deathmatch arenas from their ASCII sources.

WolfPack's campaign levels are derived from the user's own GAMEMAPS.
These five are OURS - original layouts designed for deathmatch, written
as plain ASCII in docs/data/dm/ and compiled here into the same level
dict the extractor produces, so everything downstream (convert_udmf,
the walk grid, the sim) treats them exactly like a campaign floor. No
game art lives in the source: a map is tile CODES, and the textures
those codes name come from the player's own copy at build time.

    python tools/gen_dmmaps.py

Reads  docs/data/dm/*.txt
Writes build/levels/wl6/DM<n>.json

Source format - a header of `key: value` lines, then the grid:

    name:   Kesselring
    offset: 14 14          top-left corner of the block inside the 64x64 map
    wall:   # 1            symbol -> wall tile code (repeatable)
    ...
    grid:
    ################
    #..............#
    ...

Grid symbols: '.' floor, ' ' floor, any wall symbol declared with
`wall:`, 'd' door, 'p' pushwall (a secret; it must sit in a wall run),
'S' a deathmatch start, and the item letters in ITEMS below. Every
symbol that is not a wall is floor underneath.

Areas (Wolf3D's connectivity regions, which drive door sounds and
whether an actor can hear you) are flood-filled automatically: each
region of floor bounded by walls and doors becomes one area, exactly
what a hand-numbered original map encodes.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs/data/dm"
OUT = ROOT / "build/levels/wl6"

AREATILE = 107

# item symbol -> static index (statinfo order; see statics.gen.zs)
ITEMS = {
    "c": 28,    # chaingun - the map's prize
    "m": 27,    # machine gun
    "a": 26,    # ammo clip
    "h": 25,    # first aid
    "f": 24,    # dog food
    "X": 33,    # full heal: +1 life, full health, full ammo
    "t": 31,    # treasure (score only)
}


def parse(path):
    head, grid, in_grid = {"wall": {}}, [], False
    for raw in path.read_text().splitlines():
        if in_grid:
            if raw.strip() == "" and not grid:
                continue
            grid.append(raw)
            continue
        line = raw.strip()
        if line.startswith("#!") or not line:
            continue
        if line == "grid:":
            in_grid = True
            continue
        m = re.match(r"(\w+):\s*(.*)", line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        if key == "wall":
            sym, code = val.split()
            head["wall"][sym] = int(code)
        else:
            head[key] = val
    while grid and not grid[-1].strip():
        grid.pop()
    return head, grid


def build(path, index):
    head, grid = parse(path)
    ox, oy = (int(v) for v in head["offset"].split())
    walls = head["wall"]
    default_wall = int(head.get("fill", "1"))

    # 64x64 of solid wall, then stamp the authored block into it
    cells = [{"kind": "wall", "code": default_wall} for _ in range(4096)]
    objects, starts, items, pushwalls, doors = [], [], [], [], []
    for gy, row in enumerate(grid):
        for gx, ch in enumerate(row):
            x, y = ox + gx, oy + gy
            if not (0 <= x < 64 and 0 <= y < 64):
                sys.exit(f"{path.name}: cell ({x},{y}) is off the map")
            idx = y * 64 + x
            if ch in walls:
                cells[idx] = {"kind": "wall", "code": walls[ch]}
                continue
            if ch == "p":
                # a pushwall is a WALL tile carrying a plane-1 marker
                cells[idx] = {"kind": "wall", "code": walls.get("#",
                                                                default_wall)}
                pushwalls.append((x, y))
                continue
            if ch == "d":
                doors.append((x, y))
                continue
            cells[idx] = {"kind": "floor", "area": 0,
                          "secret_exit_pad": False, "code": AREATILE}
            if ch == "S":
                starts.append((x, y))
            elif ch in ITEMS:
                items.append((x, y, ITEMS[ch]))
            elif ch not in (".", " "):
                sys.exit(f"{path.name}: unknown symbol {ch!r} at ({x},{y})")

    # doors need their orientation: walls north and south of the tile
    # means the passage runs east-west, which the map format calls
    # "vertical" (code 90); walls east and west is code 91
    for (x, y) in doors:
        ns = (cells[(y - 1) * 64 + x]["kind"] == "wall"
              and cells[(y + 1) * 64 + x]["kind"] == "wall")
        ew = (cells[y * 64 + x - 1]["kind"] == "wall"
              and cells[y * 64 + x + 1]["kind"] == "wall")
        if ns == ew:
            sys.exit(f"{path.name}: door at ({x},{y}) is not in a wall run")
        cells[y * 64 + x] = {"kind": "door", "vertical": ns,
                             "lock": "normal", "code": 90 if ns else 91}

    # flood-fill areas: floor regions bounded by walls AND doors, which
    # is exactly what a hand-numbered original encodes. Area 0 would
    # read as the secret-exit pad, so numbering starts at 1.
    area_of, nxt = {}, 1
    for i, c in enumerate(cells):
        if c["kind"] != "floor" or i in area_of:
            continue
        stack, seen = [i], set()
        while stack:
            j = stack.pop()
            if j in seen or cells[j]["kind"] != "floor":
                continue
            seen.add(j)
            jx, jy = j % 64, j // 64
            for nx, ny in ((jx + 1, jy), (jx - 1, jy),
                           (jx, jy + 1), (jx, jy - 1)):
                if 0 <= nx < 64 and 0 <= ny < 64:
                    stack.append(ny * 64 + nx)
        for j in seen:
            area_of[j] = nxt
        nxt += 1
    for j, a in area_of.items():
        cells[j]["area"] = a
        cells[j]["code"] = AREATILE + a

    # a door must join two DIFFERENT areas or it is decoration
    for (x, y) in doors:
        c = cells[y * 64 + x]
        sides = [(x - 1, y), (x + 1, y)] if not c["vertical"] \
            else [(x, y - 1), (x, y + 1)]
        # (the open sides are the ones the passage runs through)
        sides = [(x - 1, y), (x + 1, y)] if c["vertical"] \
            else [(x, y - 1), (x, y + 1)]
        got = [cells[sy * 64 + sx].get("area") for sx, sy in sides]
        if None in got:
            sys.exit(f"{path.name}: door at ({x},{y}) opens onto a wall")

    for i, (x, y) in enumerate(starts):
        objects.append({"kind": "dm_start", "x": x, "y": y,
                        "primary": i == 0})
    for (x, y, idx_) in items:
        objects.append({"kind": "static", "index": idx_, "x": x, "y": y,
                        "code": 23 + idx_})
    for (x, y) in pushwalls:
        objects.append({"kind": "pushwall", "x": x, "y": y})

    return {
        "set": "wl6", "map": 900 + index, "name": head.get("name", path.stem),
        "width": 64, "height": 64, "rlew_tag": 0,
        "plane0": [c["code"] for c in cells],
        "decoded0": cells, "objects": objects,
        "dm_starts": starts,
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = sorted(SRC.glob("*.txt"))
    if not files:
        sys.exit(f"no arena sources in {SRC}")
    for i, f in enumerate(files, 1):
        lv = build(f, i)
        floors = sum(1 for c in lv["decoded0"] if c["kind"] == "floor")
        areas = len({c["area"] for c in lv["decoded0"]
                     if c["kind"] == "floor"})
        (OUT / f"DM{i}.json").write_text(json.dumps(lv))
        print(f"DM{i} {lv['name']:<14} {floors:4d} floor tiles, "
              f"{areas:2d} areas, {len(lv['dm_starts'])} starts, "
              f"{sum(1 for o in lv['objects'] if o['kind'] == 'static')} items")


if __name__ == "__main__":
    main()
