#!/usr/bin/env python3
"""Phase 1: convert extracted levels to UDMF TEXTMAP (v1: geometry + things).

Scale: 1 Wolf tile = 64 map units. Wolf y grows south; UDMF y grows north:
tile (tx,ty) spans x [tx*64,(tx+1)*64], y [(63-ty)*64, (64-ty)*64].
Angles: east=0 north=90 west=180 south=270.

Sectors: one per Wolf AREA CODE (areas are exactly the door-bounded regions —
plane0 floor codes 107+), plus one small sector per door tile. Sector id ->
area mapping is emitted in the per-map manifest for the sim's areaconnect.
Ambush tiles (106) get their area patched from neighbors in source order
(east, north, south, west — last open neighbor wins; WL_GAME.C:740-749).

Walls: one-sided lines. Wolf shading pairs: wall code w -> VSWAP chunk
(w-1)*2 on N/S-facing edges (light) and (w-1)*2+1 on E/W-facing (dark).
[VERIFY orientation against DOSBox in the slice — swap is a one-liner.]

Doors (v1): door tile becomes its own sector with no slab yet; everything the
polyobject pass needs (axis, lock, slide dir, pocket tile) goes to the
manifest. Slide dir from WL_DRAW.C:625,693: texture = intercept -
doorposition -> slab moves toward +coord: vertical doors slide SOUTH,
horizontal doors slide EAST. Pocket = that neighbor wall tile.

Things: DoomEd mapping per docs/DOOMED_MAP.md. Skill flags: min_skill 0 ->
all; 2 (medium+) -> skill3+; 3 (hard+) -> skill4+ (skill5 mirrors 4).
"""
import json
import sys
from pathlib import Path

from wolf_common import ROOT

LEVELS = ROOT / "build" / "levels"
OUT = ROOT / "build" / "udmf"

T = 64  # map units per tile

ANGLES = {"east": 0, "north": 90, "west": 180, "south": 270,
          "northeast": 45, "northwest": 135, "southwest": 225,
          "southeast": 315}

# DoomEd numbers (docs/DOOMED_MAP.md)
ED_PLAYER1 = 1
ED_ENEMY = {("guard", "stand"): 21001, ("guard", "patrol"): 21002,
            ("officer", "stand"): 21003, ("officer", "patrol"): 21004,
            ("ss", "stand"): 21005, ("ss", "patrol"): 21006,
            ("dog", "stand"): 21007, ("dog", "patrol"): 21008,
            ("mutant", "stand"): 21009, ("mutant", "patrol"): 21010}
ED_BOSS = {"hans": 21020, "gretel": 21021, "gift": 21022, "fat": 21023,
           "schabbs": 21024, "fake_hitler": 21025, "hitler": 21026,
           "spectre": 21030, "angel": 21031, "trans": 21032, "uber": 21033,
           "will": 21034, "death_knight": 21035}
ED_GHOST = {"blinky": 21040, "clyde": 21041, "pinky": 21042, "inky": 21043}
ED_STATIC_BASE = 21100          # + statinfo index
ED_TURN_BASE = 21200            # + DIR8 index (E,NE,N,NW,W,SW,S,SE)
ED_PUSHWALL = 21210
ED_VICTORY = 21211
ED_DEAD_GUARD = 21212
DIR8 = ["east", "northeast", "north", "northwest",
        "west", "southwest", "south", "southeast"]


def area_grid(level):
    """Per-tile area number (or None for solid/door), ambush set, door list."""
    dec = level["decoded0"]
    W = H = 64
    area = [[None] * H for _ in range(W)]
    ambush = set()
    doors = []
    for idx, m in enumerate(dec):
        x, y = idx % W, idx // W
        if m["kind"] == "floor":
            area[x][y] = m["area"]
        elif m["kind"] == "ambush_floor":
            ambush.add((x, y))
        elif m["kind"] == "door":
            doors.append({"x": x, "y": y, "vertical": m["vertical"],
                          "lock": m["lock"], "code": m["code"]})
    # ambush patch, source order: east, north, south, west; LAST open wins
    for (x, y) in ambush:
        a = None
        for nx, ny in ((x + 1, y), (x, y - 1), (x, y + 1), (x - 1, y)):
            if 0 <= nx < W and 0 <= ny < H and area[nx][ny] is not None:
                a = area[nx][ny]
        area[x][y] = a
    return area, ambush, doors


def wall_code(level, x, y):
    if not (0 <= x < 64 and 0 <= y < 64):
        return 1
    m = level["decoded0"][y * 64 + x]
    return m["code"] if m["kind"] in ("wall", "elevator_switch", "exit_rail") else None


def convert(level, ceiling_color):
    area, ambush, doors = area_grid(level)
    doortile = {(d["x"], d["y"]): i for i, d in enumerate(doors)}

    # sector ids: areas sorted, then door sectors
    areas_used = sorted({a for col in area for a in col if a is not None})
    sec_of_area = {a: i for i, a in enumerate(areas_used)}
    sec_of_door = {i: len(areas_used) + i for i in range(len(doors))}

    def tile_sector(x, y):
        if (x, y) in doortile:
            return sec_of_door[doortile[(x, y)]]
        a = area[x][y]
        return None if a is None else sec_of_area[a]

    verts = {}
    lines = []
    sides = []

    def vid(x, y):
        if (x, y) not in verts:
            verts[(x, y)] = len(verts)
        return verts[(x, y)]

    def add_line(v1, v2, front_sec, tex=None, back_sec=None):
        sides.append((front_sec, tex))
        if back_sec is None:
            lines.append((vid(*v1), vid(*v2), len(sides) - 1, -1, True))
        else:
            sides.append((back_sec, None))
            lines.append((vid(*v1), vid(*v2), len(sides) - 2, len(sides) - 1, False))

    def texname(code, horiz_face):
        chunk = (code - 1) * 2 + (0 if horiz_face else 1)
        return f"WALL{chunk:03d}"

    for y in range(64):
        for x in range(64):
            s = tile_sector(x, y)
            if s is None:
                continue
            xb, yb = x * T, (63 - y) * T          # SW corner of tile in UDMF
            # north edge (faces N/S -> "horizontal" wall face, light pair)
            for (nx, ny, v1, v2, horiz) in (
                    (x, y - 1, (xb, yb + T), (xb + T, yb + T), True),    # north
                    (x, y + 1, (xb + T, yb), (xb, yb), True),            # south
                    (x - 1, y, (xb, yb), (xb, yb + T), False),           # west
                    (x + 1, y, (xb + T, yb + T), (xb + T, yb), False)):  # east
                code = wall_code(level, nx, ny)
                if code is not None:
                    add_line(v1, v2, s, texname(code, horiz))
                else:
                    ns = tile_sector(nx, ny)
                    if ns is None:
                        add_line(v1, v2, s, "WALL000")  # void guard (shouldn't happen)
                    elif ns != s and (ny > y or (ny == y and nx > x)):
                        add_line(v1, v2, s, None, back_sec=ns)

    # things
    things = []

    def thing(x, y, ed, angle=0, skills=(1, 2, 3, 4, 5), special=None):
        things.append({"x": x * T + T // 2, "y": (63 - y) * T + T // 2,
                       "type": ed, "angle": angle, "skills": skills})

    for o in level["objects"]:
        k = o["kind"]
        if k == "player_start":
            thing(o["x"], o["y"], ED_PLAYER1, ANGLES[o["dir"]])
        elif k == "enemy":
            skills = {0: (1, 2, 3, 4, 5), 2: (3, 4, 5), 3: (4, 5)}[o["min_skill"]]
            thing(o["x"], o["y"], ED_ENEMY[(o["enemy"], o["mode"])],
                  ANGLES[o["dir"]], skills)
        elif k == "boss":
            thing(o["x"], o["y"], ED_BOSS[o["enemy"]])
        elif k == "ghost":
            thing(o["x"], o["y"], ED_GHOST[o["enemy"]])
        elif k == "static":
            thing(o["x"], o["y"], ED_STATIC_BASE + o["index"])
        elif k == "turn":
            thing(o["x"], o["y"], ED_TURN_BASE + DIR8.index(o["dir"]))
        elif k == "pushwall":
            thing(o["x"], o["y"], ED_PUSHWALL)
        elif k == "victory_trigger":
            thing(o["x"], o["y"], ED_VICTORY)
        elif k == "dead_guard":
            thing(o["x"], o["y"], ED_DEAD_GUARD)

    # ambush markers ride as sim data in the manifest (per-tile), not things
    # emit TEXTMAP
    L = ['namespace = "zdoom";']
    for (vx, vy), _ in sorted(verts.items(), key=lambda kv: kv[1]):
        L.append(f"vertex {{ x = {vx}.0; y = {vy}.0; }}")
    for v1, v2, sf, sb, blocking in lines:
        parts = [f"v1 = {v1}; v2 = {v2}; sidefront = {sf};"]
        if sb >= 0:
            parts.append(f"sideback = {sb}; twosided = true;")
        if blocking:
            parts.append("blocking = true;")
        L.append("linedef { " + " ".join(parts) + " }")
    for sec, tex in sides:
        t = f' texturemiddle = "{tex}";' if tex else ""
        L.append(f"sidedef {{ sector = {sec};{t} }}")
    nsec = len(areas_used) + len(doors)
    for i in range(nsec):
        L.append(f'sector {{ heightfloor = 0; heightceiling = {T}; '
                 f'texturefloor = "FLOOR19"; textureceiling = "CEIL{ceiling_color:02X}"; '
                 f'lightlevel = 255; }}')
    for t in things:
        sk = " ".join(f"skill{s} = true;" for s in t["skills"])
        L.append(f'thing {{ x = {t["x"]}.0; y = {t["y"]}.0; type = {t["type"]}; '
                 f'angle = {t["angle"]}; {sk} single = true; coop = true; dm = true; }}')

    manifest = {
        "areas": areas_used,
        "sector_of_area": sec_of_area,
        "doors": [dict(d, sector=sec_of_door[i],
                       slide="south" if d["vertical"] else "east",
                       pocket=[d["x"], d["y"] + 1] if d["vertical"]
                              else [d["x"] + 1, d["y"]])
                  for i, d in enumerate(doors)],
        "ambush_tiles": sorted(ambush),
        "area_grid": [[area[x][y] for y in range(64)] for x in range(64)],
        "ceiling_color": ceiling_color,
    }
    return "\n".join(L) + "\n", manifest


def main():
    ceilings = json.loads((ROOT / "docs" / "data" / "ceiling_colors.json").read_text())
    total = 0
    for setname in ("wl6", "sod"):
        src = LEVELS / setname
        if not src.is_dir():
            continue
        out = OUT / setname
        out.mkdir(parents=True, exist_ok=True)
        for f in sorted(src.glob("MAP*.json")):
            level = json.loads(f.read_text())
            ceiling = ceilings[setname][level["map"]]
            textmap, manifest = convert(level, ceiling)
            stem = f.stem
            (out / f"{stem}.textmap").write_text(textmap)
            (out / f"{stem}.manifest.json").write_text(json.dumps(manifest))
            total += 1
        print(f"{setname}: converted {len(list(src.glob('MAP*.json')))} maps")
    if not total:
        sys.exit("no extracted levels; run extract_levels.py first")


if __name__ == "__main__":
    main()
