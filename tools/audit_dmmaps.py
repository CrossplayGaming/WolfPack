#!/usr/bin/env python3
"""Static audit of the deathmatch arenas.

Layout quality is mostly a human judgement, but the failures that ruin
a match are not: an item nobody can reach, a spawn that stares down a
lane at another spawn, a prize three steps from one player and thirty
from the next. Those are measurable, so they are measured here and the
build refuses arenas that fail.

    python tools/audit_dmmaps.py

Reads build/levels/wl6/DM*.json (compiled by gen_dmmaps.py).
"""
import json
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVELS = ROOT / "build/levels/wl6"

MIN_SPAWN_GAP = 12          # tiles between any two starts
# A prize must be a TRIP, never a pickup on the way out of a spawn.
# Equidistance is deliberately NOT required: starts rotate between
# lives (the engine picks the one furthest from your killer), so a
# prize near the north end is not "the north player's" - it is map
# control, which is the point. Chasing equidistance instead forced
# both prizes into the middle of every map, which made all five play
# the same and stacked the two of them in one room.
MIN_PRIZE_WALK = 10         # tiles from the NEAREST start
MIN_PRIZE_GAP = 12          # tiles between the chaingun and the full heal
CHAINGUN, FULLHEAL = 28, 33


def walkable(lv):
    """Tiles a player can stand in or pass through - doors included."""
    return {i for i, c in enumerate(lv["decoded0"])
            if c["kind"] in ("floor", "ambush_floor", "door")}


def bfs(start, ok):
    seen, q = {start}, deque([start])
    dist = {start: 0}
    while q:
        i = q.popleft()
        x, y = i % 64, i // 64
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            j = ny * 64 + nx
            if 0 <= nx < 64 and 0 <= ny < 64 and j in ok and j not in seen:
                seen.add(j)
                dist[j] = dist[i] + 1
                q.append(j)
    return dist


def clear_line(lv, a, b, ok):
    """True if two tiles share a row or column with nothing solid between
    - a hitscan lane, which is what makes a spawn unfair."""
    (ax, ay), (bx, by) = a, b
    if ax != bx and ay != by:
        return False
    step = 1 if (bx > ax or by > ay) else -1
    if ax == bx:
        rng = [(ax, y) for y in range(ay + step, by, step)]
    else:
        rng = [(x, ay) for x in range(ax + step, bx, step)]
    return all(y * 64 + x in ok for x, y in rng)


def audit(path):
    lv = json.loads(path.read_text())
    name, errs, notes = lv["name"], [], []
    ok = walkable(lv)
    starts = [(x, y) for x, y in lv["dm_starts"]]
    items = [(o["x"], o["y"], o["index"]) for o in lv["objects"]
             if o["kind"] == "static"]
    if len(starts) < 4:
        errs.append(f"{len(starts)} starts, want 4")
    if not starts:
        return name, errs, notes, 0

    dist = bfs(starts[0][1] * 64 + starts[0][0], ok)
    stranded = len(ok) - len(dist)
    if stranded:
        errs.append(f"{stranded} walkable tiles unreachable from start 1")
    for i, (x, y) in enumerate(starts[1:], 2):
        if y * 64 + x not in dist:
            errs.append(f"start {i} is cut off from start 1")
    for (x, y, idx) in items:
        if y * 64 + x not in dist:
            errs.append(f"item {idx} at ({x},{y}) is unreachable")

    for i in range(len(starts)):
        for j in range(i + 1, len(starts)):
            ax, ay = starts[i]
            bx, by = starts[j]
            gap = max(abs(ax - bx), abs(ay - by))
            if gap < MIN_SPAWN_GAP:
                errs.append(f"starts {i+1} and {j+1} are {gap} tiles apart")
            if clear_line(lv, starts[i], starts[j], ok):
                errs.append(f"starts {i+1} and {j+1} see each other "
                            "down an open lane")

    # the prize should be a contest, not a gift: walking distance from
    # every spawn to the chaingun within MAX_PRIZE_SKEW of each other
    for idx, label in ((CHAINGUN, "chaingun"), (FULLHEAL, "full heal")):
        spots = [(x, y) for (x, y, i) in items if i == idx]
        if not spots:
            errs.append(f"no {label} on the map")
            continue
        for (px, py) in spots:
            legs = []
            for (sx, sy) in starts:
                d = bfs(sy * 64 + sx, ok).get(py * 64 + px)
                if d is None:
                    errs.append(f"{label} unreachable from a start")
                    legs = []
                    break
                legs.append(d)
            if legs:
                notes.append(f"{label}: {min(legs)}-{max(legs)} tiles from "
                             f"the starts")
                if min(legs) < MIN_PRIZE_WALK:
                    errs.append(f"{label} is {min(legs)} tiles from a start "
                                "- too easy")

    # the two prizes must not share a room: a player who takes one
    # should not be standing on the other
    cg = [(x, y) for (x, y, i) in items if i == CHAINGUN]
    fh = [(x, y) for (x, y, i) in items if i == FULLHEAL]
    if cg and fh:
        d = bfs(cg[0][1] * 64 + cg[0][0], ok).get(fh[0][1] * 64 + fh[0][0])
        if d is None or d < MIN_PRIZE_GAP:
            errs.append(f"chaingun and full heal are only {d} tiles apart")
        else:
            notes.append(f"prizes {d} tiles apart")

    dead = sum(1 for i in ok
               if sum(1 for nx, ny in ((i % 64 + 1, i // 64),
                                       (i % 64 - 1, i // 64),
                                       (i % 64, i // 64 + 1),
                                       (i % 64, i // 64 - 1))
                      if ny * 64 + nx in ok) == 1)
    notes.append(f"{len(ok)} walkable tiles, {len(items)} items, "
                 f"{dead} dead ends")
    return name, errs, notes, len(ok)


def main():
    files = sorted(LEVELS.glob("DM*.json"))
    if not files:
        sys.exit("no arenas built; run tools/gen_dmmaps.py first")
    bad, sizes = 0, []
    for f in files:
        name, errs, notes, size = audit(f)
        sizes.append(size)
        print(f"{f.stem} {name}")
        for n in notes:
            print(f"    {n}")
        for e in errs:
            print(f"    FAIL {e}")
        bad += len(errs)
    if sizes and max(sizes) > min(sizes) * 1.5:
        print(f"    FAIL arenas are not comparable: {min(sizes)}-{max(sizes)} "
              "walkable tiles")
        bad += 1
    print(f"dm audit: {len(files)} arenas, {bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
