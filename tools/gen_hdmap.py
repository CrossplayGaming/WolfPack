#!/usr/bin/env python3
"""One-time generator: ECWolf<->WolfPack name map for the RMST HD pack.

Reads ECWolf's own definition files (xlat tile tables, things tables,
decorate actors) plus our generated code, and emits
docs/data/hdpack_map.json - pure name-to-name data, committed to the
repo. tools/convert_hdpack.py consumes it to convert the user's
downloaded RMST pack; no art ships with WolfPack.

Chains used (all mechanical, no image guessing):
  walls    xlat `tile N { texturenorth "X1" ... textureeast "X2" }`
           -> our WALL{(N-1)*2} (light) / +1 (dark)
  doors    the door block sits directly after the last wall tile, so
           its base is max_tile*2 - 98 in Wolf3D, 126 in Spear
  statics  xlat things {oldnum, Class} -> decorate Class sprite
           -> our S{oldnum-23:03d} (Wolf3D) / D{...} (Spear)
  weapons  ECWolf view sprite names -> ours by role; the pack maps its
           own art onto those names in its TEXTURES lump
  enemies  written separately by gen_hdenemies.py (state-label join)

Wolf3D and Spear are generated SEPARATELY and never share a section:
the two games reuse the same WALLnnn/S-D sprite numbers for different
art (Spear's tile 50 is WALL098, which is a door in Wolf3D), so one
addon pk3 per game is the only safe arrangement.

Usage: python tools/gen_hdmap.py <path-to-ecwolf.pk3>
"""
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The DOORWALL block our converter lays down after the last wall tile
# (WL_DRAW.C): normal door, jamb, elevator door, locked door. DOOR2 is
# the elevator - map codes 100/101, the elevator doors, use it.
# Wolf3D's xlat names these as ordinary tiles (50-53) so the formula
# already covers them; Spear overrides those codes with its own walls,
# so there the block has to be placed explicitly.
DOORS = ["DOOR1_1", "DOOR1_2", "SLOT1_1", "SLOT1_2",
         "DOOR2_1", "DOOR2_2", "DOOR3_1", "DOOR3_2"]

# Names no tile code can reach: ECWolf declares ELEV1 only on tile 85,
# a map code past the texture range. Resolved by image against our own
# walls (the elevator-switch face) and pinned here.
EXTRA_WALLS = {"wl6": {"ELEV1_1": "WALL040", "ELEV1_2": "WALL041"}}

# ECWolf view-weapon sprite names -> ours (same frame letters, same
# VSWAP order: READY,ATK1..4 = A..E). These are the ECWolf-side sprite
# NAMES, not the HD pack's file names: the pack maps its own art onto
# these through its TEXTURES lump (Sprite PISGA0 { Patch V_LUGR_A }),
# so the converter reads the frame->art join from the pack itself
# rather than guessing it from filenames.
WEAPONS = {"KNIF": "WKNF", "PISG": "WPIS", "MCHG": "WMGN", "CHGG": "WCHN"}

# Sprites both engines happen to name identically (the Pac-Man ghost
# easter egg) plus projectiles, whose ECWolf class names differ from
# ours. Verified by image like everything else.
MISC = {"BLKY": "BLKY", "INKY": "INKY", "PNKY": "PNKY", "CLYD": "CLYD",
        "ROCK": "MISL", "FIRE": "FIRE", "HYPO": "HYPO", "SPRK": "SPRK"}

# HUD art: ECWolf lump -> ours. Fonts are per-glyph on our side and a
# single sheet on theirs, so only the digit set crosses over.
GRAPHICS = {
    "STBAR": "STATBAR", "STKEYS1": "GOLDKEY", "STKEYS2": "SILVKEY",
    "KNIFE": "KNIFEP", "PISTOL": "GUNP", "MACHGUN": "MGUNP",
    "GATLGUN": "GATLINGP", "L_GUY1": "L_GUY",
}
GRAPHICS.update({f"FONTN{48 + d:03d}": f"N_{d}" for d in range(10)})


def tiles(xlat):
    """tile code -> (light face, dark face) for real wall tiles."""
    out = {}
    for m in re.finditer(
            r'tile\s+(\d+)\s*\{\s*'
            r'texturenorth\s*=\s*"(\w+)";\s*texturesouth\s*=\s*"\w+";\s*'
            r'textureeast\s*=\s*"(\w+)"', xlat):
        code = int(m.group(1))
        if code <= 64:                  # 65+ are door/special codes
            out[code] = (m.group(2), m.group(3))
    return out


def things(xlat):
    """ECWolf class name -> map thing number."""
    out = {}
    for m in re.finditer(r'\{(\d+),\s*\$?(\w+),\s*\d+,\s*\d+,\s*\d+\}', xlat):
        out[m.group(2)] = int(m.group(1))
    return out


def spawn_sprites(z):
    """decorate class -> the 4-char sprite its Spawn state uses."""
    dec = ""
    for n in z.namelist():
        if n.startswith("actors/wolf/") and n.endswith(".txt"):
            dec += z.read(n).decode("latin-1") + "\n"
    out = {}
    for m in re.finditer(r'actor\s+(\w+)(?:\s*:\s*(\w+))?[^{]*\{(.*?)\n\}',
                         dec, re.S):
        sm = re.search(r'[Ss]pawn:\s*\n?\s*(\w{4})\s', m.group(3))
        if sm:
            out[m.group(1)] = sm.group(1)
    return out


def game_section(tile_map, thing_map, sprites, prefix, game):
    walls, statics = {}, {}
    for code, (light, dark) in tile_map.items():
        walls[light] = f"WALL{(code - 1) * 2:03d}"
        walls[dark] = f"WALL{(code - 1) * 2 + 1:03d}"
    base = max(tile_map) * 2            # door block follows the tiles
    for i, name in enumerate(DOORS):
        walls.setdefault(name, f"WALL{base + i:03d}")
    for cname, oldnum in thing_map.items():
        spr = sprites.get(cname)
        if spr and 23 <= oldnum <= 93:
            statics[spr] = f"{prefix}{oldnum - 23:03d}"
    walls.update(EXTRA_WALLS.get(game, {}))
    return {"walls": walls, "sprites": statics}


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: gen_hdmap.py <ecwolf.pk3>")
    z = zipfile.ZipFile(sys.argv[1])
    wolf = z.read("xlat/wolf3d.txt").decode("latin-1")
    # spear.txt `include`s wolf3d.txt then overrides tiles 50-63
    spear_extra = z.read("xlat/spear.txt").decode("latin-1")
    sprites = spawn_sprites(z)

    wolf_tiles = tiles(wolf)
    spear_tiles = dict(wolf_tiles)
    spear_tiles.update(tiles(spear_extra))
    wolf_things = things(wolf)
    spear_things = dict(wolf_things)
    spear_things.update(things(spear_extra))

    path = ROOT / "docs/data/hdpack_map.json"
    old = json.loads(path.read_text()) if path.exists() else {}
    out = {
        "wl6": game_section(wolf_tiles, wolf_things, sprites, "S", "wl6"),
        "sod": game_section(spear_tiles, spear_things, sprites, "D", "sod"),
        "weapons": dict(WEAPONS),
        "misc": dict(MISC),
        "graphics": dict(GRAPHICS),
        # written by gen_hdenemies.py; preserved across runs
        "enemies": old.get("enemies", {}),
    }
    path.write_text(json.dumps(out, indent=1, sort_keys=True) + "\n")
    for g in ("wl6", "sod"):
        print(f"{g}: {len(out[g]['walls'])} walls, "
              f"{len(out[g]['sprites'])} statics")
    print(f"weapons {len(out['weapons'])}, misc {len(out['misc'])}, "
          f"graphics {len(out['graphics'])}, enemies {len(out['enemies'])}")


if __name__ == "__main__":
    main()
