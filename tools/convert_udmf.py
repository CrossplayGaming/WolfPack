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

# Door pages are DERIVED, not fixed: the source defines
# DOORWALL = PMSpriteStart - 8 (WL_DRAW.C:19), i.e. the last eight wall
# pages before the sprites begin. WL6 starts sprites at 106 so DOORWALL
# is 98; Spear has 28 more walls and starts at 134, so its doors live at
# 126. Hardcoding WL6's 98 drew Spear's doors as a mid-set rock texture
# (user repro: brown rock doors on floor one).
#   +0/+1 normal   +2/+3 jamb   +4/+5 elevator   +6/+7 locked
DOOR_OFF = {"normal": 0, "gold": 6, "silver": 6, "lock3": 6, "lock4": 6,
            "elevator": 4}


def doorwall_for(setname):
    import json as _j
    mf = ROOT / "build" / "vswap" / setname / "manifest.json"
    if mf.exists():
        return _j.loads(mf.read_text())["spritestart"] - 8
    return 98                       # WL6 fallback
LOCK_NUM = {"normal": 0, "gold": 1, "silver": 2, "lock3": 3, "lock4": 4,
            "elevator": 5}
SLABW = 8          # slab thickness; pocket channel matches

# Curated deathmatch starts (map design, not derivation): Hans's level
# doubles as the 1v1 arena - one spawn in the starting room, one in
# Hans's chamber, per the layout read of build/levels/wl6/MAP08.json
# (start corridor bottom, boss chamber top, pillared hall between).
# Keyed (set, map index); value list of (tx, ty, angle). When present,
# these REPLACE the max-spread dm_spots for that map.
DM_OVERRIDES = {
    ("wl6", 8): [(34, 58, 90),     # starting room, facing north
                 (34, 11, 270)],   # Hans's chamber, facing south
}

# Lobby (multiplayer staging): a copy of Hans's level with the fight
# stripped out. All players spawn together in the big pillared hall;
# episode doors / skill switches wire in with the lobby flow.
LOBBY_SOURCE = ("wl6", 8)
LOBBY_START = (34, 34, "north")    # center aisle of the pillared hall


def make_lobby(level):
    lv = dict(level)
    lv["name"] = "Lobby"
    objs = []
    for o in level["objects"]:
        # no boss, no victory tiles (walking the hall must not end the
        # episode), no original start - everything else stays
        if o["kind"] in ("boss", "enemy", "ghost", "victory_trigger",
                         "player_start"):
            continue
        objs.append(o)
    tx, ty, d = LOBBY_START
    objs.append({"kind": "player_start", "dir": d, "x": tx, "y": ty,
                 "code": 19})
    lv["objects"] = objs
    return lv


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


def wall_code(level, x, y, pwtile=None):
    if not (0 <= x < 64 and 0 <= y < 64):
        return 1
    if pwtile and (x, y) in pwtile:
        return None            # pushwall tiles are dynamic (polyobject cube)
    m = level["decoded0"][y * 64 + x]
    return m["code"] if m["kind"] in ("wall", "elevator_switch", "exit_rail") else None


def convert(level, ceiling_color):
    area, ambush, doors = area_grid(level)
    doortile = {(d["x"], d["y"]): i for i, d in enumerate(doors)}

    # pushwalls: plane-1 code 98 on a solid tile. The cube is a 64x64
    # polyobject parked on its own sector; travel tiles are open floor in
    # the map data (MovePWalls stops on any nonzero actorat — walls block).
    dec = level["decoded0"]
    pushwalls = [{"x": o["x"], "y": o["y"],
                  "code": dec[o["y"] * 64 + o["x"]]["code"]}
                 for o in level["objects"] if o["kind"] == "pushwall"]
    pwset = {(p["x"], p["y"]) for p in pushwalls}
    for p in pushwalls:
        # static max travel per push dir (E,N,W,S), capped at 2 (PWALL-001);
        # parked pushwalls counted solid (they block unless already moved)
        maxt = []
        for dx, dy in ((1, 0), (0, -1), (-1, 0), (0, 1)):
            n = 0
            for step in (1, 2):
                tx, ty = p["x"] + dx * step, p["y"] + dy * step
                if not (0 <= tx < 64 and 0 <= ty < 64):
                    break
                m = dec[ty * 64 + tx]
                if m["kind"] not in ("floor", "ambush_floor"):
                    break
                if (tx, ty) in doortile or (tx, ty) in pwset:
                    break
                n = step
            maxt.append(n)
        p["maxtravel"] = maxt
    pwtile = {(p["x"], p["y"]): i for i, p in enumerate(pushwalls)}

    areas_used = sorted({a for col in area for a in col if a is not None})
    sec_of_area = {a: i for i, a in enumerate(areas_used)}
    sec_of_door = {i: len(areas_used) + i for i in range(len(doors))}
    sec_of_pw = {i: len(areas_used) + len(doors) + i
                 for i in range(len(pushwalls))}
    stash_sec = len(areas_used) + len(doors) + len(pushwalls)

    def tile_sector(x, y):
        if (x, y) in doortile:
            return sec_of_door[doortile[(x, y)]]
        if (x, y) in pwtile:
            return sec_of_pw[pwtile[(x, y)]]
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
            dw = doorwall_for(level["set"])
            return f"WALL{dw + (2 if horiz_face else 3):03d}"
        return f"WALL{(code - 1) * 2 + (0 if horiz_face else 1):03d}"

    pocket_edge = {}        # door tile -> which edge opens into the pocket
    for d in doors:
        pocket_edge[(d["x"], d["y"])] = "south" if d["vertical"] else "east"

    def emit_pocket(d, s):
        """Pocket-side edge: jamb wall split 28/8/28 with the middle open
        into a channel carved in the pocket tile. The slab's black end cap
        fills the 8-unit slot exactly when fully open — the original's
        'disappears into the black slot' look, with no coplanar surfaces."""
        x, y = d["x"], d["y"]
        xb, yb = x * T, (63 - y) * T
        w = SLABW // 2
        # jamb pages are DERIVED (DOORWALL+2/+3); these were hardcoded to
        # WL6's 100/101, which in Spear's wall set are plain stone - the
        # pocket side is exactly one flank of every door, which is why
        # only one side of each doorway looked wrong (user repro)
        dw = doorwall_for(level["set"])
        J_H, J_V = f"WALL{dw + 2:03d}", f"WALL{dw + 3:03d}"
        if d["vertical"]:                     # channel in the south tile
            xm = xb + T // 2
            add_line((xb + T, yb), (xm + w, yb), s, J_H)
            add_line((xm - w, yb), (xb, yb), s, J_H)
            add_line((xm - w, yb - T), (xm - w, yb), s, J_V)
            add_line((xm + w, yb), (xm + w, yb - T), s, J_V)
            add_line((xm + w, yb - T), (xm - w, yb - T), s, J_H)
        else:                                 # channel in the east tile
            ym = yb + T // 2
            add_line((xb + T, yb + T), (xb + T, ym + w), s, J_V)
            add_line((xb + T, ym - w), (xb + T, yb), s, J_V)
            add_line((xb + T, ym + w), (xb + 2 * T, ym + w), s, J_H)
            add_line((xb + 2 * T, ym - w), (xb + T, ym - w), s, J_H)
            add_line((xb + 2 * T, ym + w), (xb + 2 * T, ym - w), s, J_V)

    for y in range(64):
        for x in range(64):
            s = tile_sector(x, y)
            if s is None:
                continue
            xb, yb = x * T, (63 - y) * T
            front_is_door = (x, y) in doortile
            pedge = pocket_edge.get((x, y))
            for (nx, ny, v1, v2, horiz, edge) in (
                    (x, y - 1, (xb, yb + T), (xb + T, yb + T), True, "north"),
                    (x, y + 1, (xb + T, yb), (xb, yb), True, "south"),
                    (x - 1, y, (xb, yb), (xb, yb + T), False, "west"),
                    (x + 1, y, (xb + T, yb + T), (xb + T, yb), False, "east")):
                if pedge == edge:
                    continue        # emitted by emit_pocket below
                code = wall_code(level, nx, ny, pwtile)
                if code is not None:
                    add_line(v1, v2, s, texname(code, horiz, front_is_door))
                else:
                    ns = tile_sector(nx, ny)
                    if ns is None:
                        add_line(v1, v2, s, "WALL000")
                    elif ns != s and (ny > y or (ny == y and nx > x)):
                        add_line(v1, v2, s, None, back_sec=ns)

    for i, d in enumerate(doors):
        emit_pocket(d, sec_of_door[i])

    # ------------------------------------------------------------------
    # things
    # ------------------------------------------------------------------
    things = []

    def thing(tx, ty, ed, angle=0, skills=(1, 2, 3, 4, 5), args=None,
              raw=None):
        pos = raw if raw else (tx * T + T // 2, (63 - ty) * T + T // 2)
        things.append({"x": pos[0], "y": pos[1], "type": ed, "angle": angle,
                       "skills": skills, "args": args})

    # netgame starts (MP audit): co-op players 2-8 on the free floor
    # tiles BFS-nearest the player 1 start, deathmatch starts on eight
    # max-spread free tiles. Original maps have exactly one start.
    dec = level["decoded0"]
    occupied = {(o["x"], o["y"]) for o in level["objects"]
                if o["kind"] != "player_start"}

    def freetile(tx, ty):
        if not (0 <= tx < 64 and 0 <= ty < 64):
            return False
        t = dec[ty * 64 + tx]
        return t["kind"] == "floor" and (tx, ty) not in occupied

    def coop_spots(sx, sy, n):
        seen = {(sx, sy)}
        queue = [(sx, sy)]
        out = []
        while queue and len(out) < n:
            cx, cy = queue.pop(0)
            for dx, dy in ((1,0), (-1,0), (0,1), (0,-1)):
                nx, ny = cx + dx, cy + dy
                if (nx, ny) in seen or not freetile(nx, ny):
                    continue
                seen.add((nx, ny))
                queue.append((nx, ny))
                out.append((nx, ny))
        return out

    def dm_spots(n):
        cand = [(x, y) for y in range(64) for x in range(64)
                if freetile(x, y)]
        if not cand:
            return []
        picks = [cand[0]]
        while len(picks) < n and cand:
            best, bd = None, -1
            for c in cand:
                d = min((c[0]-q[0])**2 + (c[1]-q[1])**2 for q in picks)
                if d > bd:
                    bd, best = d, c
            if best is None or bd <= 8:
                break
            picks.append(best)
        return picks

    for o in level["objects"]:
        k = o["kind"]
        if k == "dm_start":
            # our own arenas (gen_dmmaps.py) place every start by hand,
            # so the max-spread search below never runs on them. The
            # first one doubles as the single-player start, which is
            # what lets an arena be walked and screenshotted solo.
            thing(o["x"], o["y"], 11, o.get("angle", 0))
            if o.get("primary"):
                thing(o["x"], o["y"], ED_PLAYER1, o.get("angle", 0))
        elif k == "player_start":
            thing(o["x"], o["y"], ED_PLAYER1, ANGLES[o["dir"]])
            spots = coop_spots(o["x"], o["y"], 7)
            for i, (cx, cy) in enumerate(spots[:7]):
                # players 2-4: doomednums 2-4; players 5-8: 4001-4004
                ed = 2 + i if i < 3 else 4001 + (i - 3)
                thing(cx, cy, ed, ANGLES[o["dir"]])
            if level.get("name") == "Lobby":
                pass                       # staging only - no DM starts
            elif (level["set"], level["map"]) in DM_OVERRIDES:
                for dx, dy, dang in DM_OVERRIDES[(level["set"],
                                                  level["map"])]:
                    thing(dx, dy, 11, dang)
            else:
                for dx, dy in dm_spots(8):
                    thing(dx, dy, 11, 0)
        elif k == "enemy":
            skills = {0: (1, 2, 3, 4, 5), 2: (3, 4, 5), 3: (4, 5)}[o["min_skill"]]
            thing(o["x"], o["y"], ED_ENEMY[(o["enemy"], o["mode"])],
                  ANGLES[o["dir"]], skills)
        elif k == "boss":
            thing(o["x"], o["y"], ED_BOSS[o["enemy"]])
        elif k == "ghost":
            thing(o["x"], o["y"], ED_GHOST[o["enemy"]])
        elif k == "static":
            # per-set static ranges: WL6 21100+, Spear 21300+ (the
            # two builds' statinfo arrays diverge from index 15)
            base = 21300 if level["set"] == "sod" else ED_STATIC_BASE
            thing(o["x"], o["y"], base + o["index"])
        elif k == "turn":
            thing(o["x"], o["y"], ED_TURN_BASE + DIR8.index(o["dir"]))
        elif k == "pushwall":
            pass                # emitted with its polyobject below
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

        dw = doorwall_for(level["set"])
        off = DOOR_OFF[d["lock"]]
        face_v, face_h = dw + off, dw + off + 1
        # end caps are pure black: the pocket-side cap fills the jamb's slot
        # exactly at full open, reading as the original's empty black slot
        if d["vertical"]:
            sw, sl = SLABW // 2, T // 2       # thin in x, long in y
            fx1, fy1, fx2, fy2 = cx - sw, cy - sl, cx + sw, cy + sl
            long_tex, cap_tex = f"WALL{face_v:03d}", "WBLACK"
        else:
            sw, sl = T // 2, SLABW // 2       # long in x, thin in y
            fx1, fy1, fx2, fy2 = cx - sw, cy - sl, cx + sw, cy + sl
            long_tex, cap_tex = f"WALL{face_h:03d}", "WBLACK"
        # slab lines CCW (front faces outward); first carries Polyobj_StartLine.
        # Orientation rule (charter DOOR-014): door textures are WORLD-anchored
        # (WL_DRAW.C HitVert/HorizDoor have no per-side reversal, unlike
        # walls): column 0 at the NORTH end (vertical) / WEST end (horizontal).
        # GZDoom puts image-left at v1, so the face whose v1 is the column-0
        # end renders unflipped and the OPPOSITE face carries the mirror:
        #   vertical:   west face (v1 north) plain, EAST face flipped
        #   horizontal: south face (v1 west) plain, NORTH face flipped
        vertical = d["vertical"]
        top_tex = cap_tex if vertical else long_tex
        side_tex = long_tex if vertical else cap_tex
        add_line((fx2, fy2), (fx1, fy2), stash_sec, top_tex,
                 special=1, arg0=poid, flipx=(not vertical))
        add_line((fx1, fy2), (fx1, fy1), stash_sec, side_tex)
        add_line((fx1, fy1), (fx2, fy1), stash_sec, top_tex)
        add_line((fx2, fy1), (fx2, fy2), stash_sec, side_tex,
                 flipx=vertical)

        dx, dy = d["x"], d["y"]
        center = (dx * T + T // 2, (63 - dy) * T + T // 2)
        thing(0, 0, ED_POLY_ANCHOR, angle=poid, raw=(cx, cy))
        thing(0, 0, ED_POLY_START, angle=poid, raw=center)
        thing(0, 0, ED_DOOR, raw=center,
              args=[poid, 1 if d["vertical"] else 0, LOCK_NUM[d["lock"]]])
        d["polyid"] = poid

    # ------------------------------------------------------------------
    # pushwall cubes: 64x64 polyobjects with the tile's own wall pair.
    # Face ordering matches normal walls (as-authored from every side —
    # walls have the per-side reversal, DOOR-014 note).
    # ------------------------------------------------------------------
    for j, p in enumerate(pushwalls):
        poid = len(doors) + 1 + j
        cx, cy = -160, (len(doors) + j) * 128 + 64
        x1, y1, x2, y2 = cx - 48, cy - 48, cx + 48, cy + 48
        add_line((x1, y2), (x2, y2), stash_sec, "WALL000")
        add_line((x2, y2), (x2, y1), stash_sec, "WALL000")
        add_line((x2, y1), (x1, y1), stash_sec, "WALL000")
        add_line((x1, y1), (x1, y2), stash_sec, "WALL000")

        h_tex = f"WALL{(p['code'] - 1) * 2:03d}"        # N/S faces
        v_tex = f"WALL{(p['code'] - 1) * 2 + 1:03d}"    # E/W faces
        fx1, fy1, fx2, fy2 = cx - 32, cy - 32, cx + 32, cy + 32
        add_line((fx2, fy2), (fx1, fy2), stash_sec, h_tex,
                 special=1, arg0=poid)
        add_line((fx1, fy2), (fx1, fy1), stash_sec, v_tex)
        add_line((fx1, fy1), (fx2, fy1), stash_sec, h_tex)
        add_line((fx2, fy1), (fx2, fy2), stash_sec, v_tex)

        center = (p["x"] * T + T // 2, (63 - p["y"]) * T + T // 2)
        thing(0, 0, ED_POLY_ANCHOR, angle=poid, raw=(cx, cy))
        thing(0, 0, ED_POLY_START, angle=poid, raw=center)
        thing(0, 0, ED_PUSHWALL, raw=center,
              args=[poid] + p["maxtravel"])
        p["polyid"] = poid

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
    nsec = len(areas_used) + len(doors) + len(pushwalls) + 1
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

    # sim grid lump: solid/door/pushwall map + area codes, parsed by the
    # ZScript WolfLevel handler (actorat/areaconnect foundation)
    grid_lines = []
    for gy in range(64):
        row = ""
        for gx in range(64):
            if (gx, gy) in doortile:
                row += "D"
            elif (gx, gy) in pwtile:
                row += "P"
            elif wall_code(level, gx, gy) is not None:
                row += "E" if dec[gy * 64 + gx]["kind"] == "elevator_switch"                     else "#"
            elif (gx, gy) in ambush:
                row += "a"
            else:
                row += "."
        grid_lines.append(row)
    grid_lines.append("")  # separator
    for gy in range(64):
        row = ""
        for gx in range(64):
            a = area[gx][gy]
            row += "-" if a is None else chr(65 + a)
        grid_lines.append(row)
    gridtext = "\n".join(grid_lines) + "\n"

    manifest = {
        "areas": areas_used,
        "sector_of_area": sec_of_area,
        "doors": [dict(d, sector=sec_of_door[i],
                       slide="south" if d["vertical"] else "east",
                       pocket=[d["x"], d["y"] + 1] if d["vertical"]
                              else [d["x"] + 1, d["y"]])
                  for i, d in enumerate(doors)],
        "pushwalls": [dict(p, sector=sec_of_pw[i])
                      for i, p in enumerate(pushwalls)],
        "ambush_tiles": sorted(ambush),
        "area_grid": [[area[x][y] for y in range(64)] for x in range(64)],
        "ceiling_color": ceiling_color,
    }
    return "\n".join(L) + "\n", manifest, gridtext


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
            textmap, manifest, gridtext = convert(level, ceiling)
            stem = f.stem
            (out / f"{stem}.textmap").write_text(textmap)
            (out / f"{stem}.manifest.json").write_text(json.dumps(manifest))
            (out / f"{stem}.grid.txt").write_text(gridtext)
            total += 1
            if setname == "sod" and level["map"] == 0:
                # Spear lobby: the same hall (so lobby.zs's zone map
                # still applies) rendered with Spear's wall set. Its
                # statics are stripped - WL6 static indices mean
                # different objects in Spear's statinfo array.
                wl6dir = LEVELS / "wl6"
                src8 = wl6dir / "MAP08.json"
                if src8.exists():
                    lv = make_lobby(json.loads(src8.read_text()))
                    lv["set"] = "sod"
                    lv["objects"] = [o for o in lv["objects"]
                                     if o["kind"] != "static"]
                    ltm, lman, lgrid = convert(lv, ceiling)
                    (out / "LOBBY.textmap").write_text(ltm)
                    (out / "LOBBY.manifest.json").write_text(
                        json.dumps(lman))
                    (out / "LOBBY.grid.txt").write_text(lgrid)
                    print(f"{setname}: + LOBBY (Spear-skinned hall)")
            if (setname, level["map"]) == LOBBY_SOURCE:
                ltm, lman, lgrid = convert(make_lobby(level), ceiling)
                (out / "LOBBY.textmap").write_text(ltm)
                (out / "LOBBY.manifest.json").write_text(json.dumps(lman))
                (out / "LOBBY.grid.txt").write_text(lgrid)
                print(f"{setname}: + LOBBY (from MAP{level['map']:02d})")
        # our own deathmatch arenas, compiled by gen_dmmaps.py from the
        # ASCII sources in docs/data/dm - not derived from anyone's
        # game data, so they go through the same writer and nothing
        # downstream has to know the difference
        if setname == "wl6":
            for f in sorted(src.glob("DM*.json")):
                lv = json.loads(f.read_text())
                tm, man, gr = convert(lv, ceilings["wl6"][1])
                (out / f"{f.stem}.textmap").write_text(tm)
                (out / f"{f.stem}.manifest.json").write_text(json.dumps(man))
                (out / f"{f.stem}.grid.txt").write_text(gr)
                print(f"{setname}: + {f.stem} ({lv['name']})")
        print(f"{setname}: converted {len(list(src.glob('MAP*.json')))} maps")
    if not total:
        sys.exit("no extracted levels; run extract_levels.py first")


if __name__ == "__main__":
    main()
