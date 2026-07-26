#!/usr/bin/env python3
"""Phase 1: convert extracted levels to UDMF TEXTMAP (v2: polyobject doors).

Scale: 1 Wolf tile = 64 map units. Wolf y grows south; UDMF y grows north:
tile (tx,ty) spans x [tx*64,(tx+1)*64], y [(63-ty)*64, (64-ty)*64].
Angles: east=0 north=90 west=180 south=270.

Sectors: one per Wolf AREA CODE (areas are exactly the door-bounded regions —
plane0 floor codes 107+), plus one per door tile (pocket channel included),
plus one stash sector holding all door-slab polyobjects.

Walls: one-sided lines. Wall code w -> VSWAP chunk (w-1)*2 on N/S faces and
(w-1)*2+1 on E/W faces. Door-adjacent wall tiles are jamb-marked (SpawnDoor
|0x40, WL_ACT1.C:373-384) and render the jamb pages on ALL faces:
DOORWALL+2 (WALL100) N/S, DOORWALL+3 (WALL101) E/W (WL_DRAW.C:525,597).

Doors: slab = 8x64 polyobject authored in the stash, spawned at the door
tile center (anchor 9300 / start spot 9301, po number in the angle field).
Slide dir from WL_DRAW.C:625,693 (texture = intercept - doorposition):
vertical doors slide SOUTH, horizontal doors slide EAST, into a carved
pocket channel in that neighbor wall tile. Door faces: normal WALL098/099,
locked WALL104/105, elevator WALL102/103 (WL_DRAW.C:658-671, DOORWALL=98).
A WolfDoor controller thing (DoomEd 21220) carries args [po, vertical, lock].

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
ED_STATIC_BASE = 21100
ED_TURN_BASE = 21200
ED_PUSHWALL = 21210
ED_VICTORY = 21211
ED_DEAD_GUARD = 21212
ED_DOOR = 21220
ED_POLY_ANCHOR = 9300
ED_POLY_START = 9301
DIR8 = ["east", "northeast", "north", "northwest",
        "west", "southwest", "south", "southeast"]

DOOR_FACE = {"normal": (98, 99), "gold": (104, 105), "silver": (104, 105),
             "lock3": (104, 105), "lock4": (104, 105), "elevator": (102, 103)}
LOCK_NUM = {"normal": 0, "gold": 1, "silver": 2, "lock3": 3, "lock4": 4,
            "elevator": 5}
SLABW = 8          # slab thickness; pocket channel matches


def area_grid(level):
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

    areas_used = sorted({a for col in area for a in col if a is not None})
    sec_of_area = {a: i for i, a in enumerate(areas_used)}
    sec_of_door = {i: len(areas_used) + i for i in range(len(doors))}
    stash_sec = len(areas_used) + len(doors)

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

    def add_line(v1, v2, front_sec, tex=None, back_sec=None,
                 special=0, arg0=0, flipx=False):
        sides.append((front_sec, tex, flipx))
        if back_sec is None:
            lines.append((vid(*v1), vid(*v2), len(sides) - 1, -1, True,
                          special, arg0))
        else:
            sides.append((back_sec, None, False))
            lines.append((vid(*v1), vid(*v2), len(sides) - 2, len(sides) - 1,
                          False, special, arg0))

    def texname(code, horiz_face, front_is_door):
        # jamb page ONLY on faces looking into the door lane (DOOR-013,
        # WL_DRAW.C:521-527 — approach tile must be the door tile)
        if front_is_door:
            return f"WALL{100 if horiz_face else 101:03d}"
        return f"WALL{(code - 1) * 2 + (0 if horiz_face else 1):03d}"

    def emit_channel(d, s):
        """Sealed pocket channel behind the wall plane: the slab slides
        through the (non-blocking-to-polyobjects) boundary wall and hides
        completely, like the original's flush disappearance."""
        x, y = d["x"], d["y"]
        xb, yb = x * T, (63 - y) * T
        w = SLABW // 2
        if d["vertical"]:                     # channel in the south tile
            xm = xb + T // 2
            add_line((xm - w, yb), (xm + w, yb), s, "WALL100")
            add_line((xm + w, yb - T), (xm - w, yb - T), s, "WALL100")
            add_line((xm - w, yb - T), (xm - w, yb), s, "WALL101")
            add_line((xm + w, yb), (xm + w, yb - T), s, "WALL101")
        else:                                 # channel in the east tile
            ym = yb + T // 2
            add_line((xb + T, ym - w), (xb + T, ym + w), s, "WALL101")
            add_line((xb + 2 * T, ym + w), (xb + 2 * T, ym - w), s, "WALL101")
            add_line((xb + T, ym + w), (xb + 2 * T, ym + w), s, "WALL100")
            add_line((xb + 2 * T, ym - w), (xb + T, ym - w), s, "WALL100")

    for y in range(64):
        for x in range(64):
            s = tile_sector(x, y)
            if s is None:
                continue
            xb, yb = x * T, (63 - y) * T
            front_is_door = (x, y) in doortile
            for (nx, ny, v1, v2, horiz) in (
                    (x, y - 1, (xb, yb + T), (xb + T, yb + T), True),
                    (x, y + 1, (xb + T, yb), (xb, yb), True),
                    (x - 1, y, (xb, yb), (xb, yb + T), False),
                    (x + 1, y, (xb + T, yb + T), (xb + T, yb), False)):
                code = wall_code(level, nx, ny)
                if code is not None:
                    add_line(v1, v2, s, texname(code, horiz, front_is_door))
                else:
                    ns = tile_sector(nx, ny)
                    if ns is None:
                        add_line(v1, v2, s, "WALL000")
                    elif ns != s and (ny > y or (ny == y and nx > x)):
                        add_line(v1, v2, s, None, back_sec=ns)

    for i, d in enumerate(doors):
        emit_channel(d, sec_of_door[i])

    # ------------------------------------------------------------------
    # things
    # ------------------------------------------------------------------
    things = []

    def thing(tx, ty, ed, angle=0, skills=(1, 2, 3, 4, 5), args=None,
              raw=None):
        pos = raw if raw else (tx * T + T // 2, (63 - ty) * T + T // 2)
        things.append({"x": pos[0], "y": pos[1], "type": ed, "angle": angle,
                       "skills": skills, "args": args})

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

    # ------------------------------------------------------------------
    # door slabs: stash cells west of the grid, one polyobject per door
    # ------------------------------------------------------------------
    for i, d in enumerate(doors):
        poid = i + 1
        cx, cy = -160, i * 128 + 64
        x1, y1, x2, y2 = cx - 16, cy - 48, cx + 16, cy + 48
        # stash cell walls (interior on the right -> clockwise)
        add_line((x1, y2), (x2, y2), stash_sec, "WALL000")
        add_line((x2, y2), (x2, y1), stash_sec, "WALL000")
        add_line((x2, y1), (x1, y1), stash_sec, "WALL000")
        add_line((x1, y1), (x1, y2), stash_sec, "WALL000")

        face_v, face_h = DOOR_FACE[d["lock"]]
        if d["vertical"]:
            sw, sl = SLABW // 2, T // 2       # thin in x, long in y
            fx1, fy1, fx2, fy2 = cx - sw, cy - sl, cx + sw, cy + sl
            long_tex, cap_tex = f"WALL{face_v:03d}", "WALL100"
        else:
            sw, sl = T // 2, SLABW // 2       # long in x, thin in y
            fx1, fy1, fx2, fy2 = cx - sw, cy - sl, cx + sw, cy + sl
            long_tex, cap_tex = f"WALL{face_h:03d}", "WALL101"
        # slab lines CCW (front faces outward); first carries Polyobj_StartLine.
        # One long face is mirrored (scalex -1) so the handle sits at the same
        # WORLD position from both sides, as the original's world-coordinate
        # texture mapping does (WL_DRAW.C: texture = intercept - doorposition).
        vertical = d["vertical"]
        top_tex = cap_tex if vertical else long_tex
        side_tex = long_tex if vertical else cap_tex
        add_line((fx2, fy2), (fx1, fy2), stash_sec, top_tex,
                 special=1, arg0=poid, flipx=(not vertical))
        add_line((fx1, fy2), (fx1, fy1), stash_sec, side_tex,
                 flipx=vertical)
        add_line((fx1, fy1), (fx2, fy1), stash_sec, top_tex)
        add_line((fx2, fy1), (fx2, fy2), stash_sec, side_tex)

        dx, dy = d["x"], d["y"]
        center = (dx * T + T // 2, (63 - dy) * T + T // 2)
        thing(0, 0, ED_POLY_ANCHOR, angle=poid, raw=(cx, cy))
        thing(0, 0, ED_POLY_START, angle=poid, raw=center)
        thing(0, 0, ED_DOOR, raw=center,
              args=[poid, 1 if d["vertical"] else 0, LOCK_NUM[d["lock"]]])
        d["polyid"] = poid

    # ------------------------------------------------------------------
    # emit TEXTMAP
    # ------------------------------------------------------------------
    L = ['namespace = "zdoom";']
    for (vx, vy), _ in sorted(verts.items(), key=lambda kv: kv[1]):
        L.append(f"vertex {{ x = {vx}.0; y = {vy}.0; }}")
    for v1, v2, sf, sb, blocking, special, arg0 in lines:
        parts = [f"v1 = {v1}; v2 = {v2}; sidefront = {sf};"]
        if sb >= 0:
            parts.append(f"sideback = {sb}; twosided = true;")
        if blocking:
            parts.append("blocking = true;")
        if special:
            parts.append(f"special = {special}; arg0 = {arg0};")
        L.append("linedef { " + " ".join(parts) + " }")
    for sec, tex, flipx in sides:
        t = f' texturemiddle = "{tex}";' if tex else ""
        if flipx:
            t += " scalex_mid = -1.0;"
        L.append(f"sidedef {{ sector = {sec};{t} }}")
    nsec = len(areas_used) + len(doors) + 1
    for i in range(nsec):
        L.append(f'sector {{ heightfloor = 0; heightceiling = {T}; '
                 f'texturefloor = "FLOOR19"; textureceiling = "CEIL{ceiling_color:02X}"; '
                 f'lightlevel = 255; }}')
    for t in things:
        sk = " ".join(f"skill{s} = true;" for s in t["skills"])
        argstr = ""
        if t["args"]:
            argstr = " " + " ".join(f"arg{i} = {v};"
                                    for i, v in enumerate(t["args"]) if v)
        L.append(f'thing {{ x = {t["x"]}.0; y = {t["y"]}.0; type = {t["type"]}; '
                 f'angle = {t["angle"]}; {sk} single = true; coop = true; '
                 f'dm = true;{argstr} }}')

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
