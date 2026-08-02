#!/usr/bin/env python3
"""One-time generator: ECWolf<->WolfPack name map for the RMST HD pack.

Reads ECWolf's own definition files (xlat tile table, things table,
decorate actors) plus our generated code, and emits
docs/data/hdpack_map.json - pure name-to-name data, committed to the
repo. tools/convert_hdpack.py consumes it to convert the user's
downloaded RMST pack; no art ships with WolfPack.

Chains used (all mechanical, no image guessing):
  walls    xlat `tile N { texturenorth "X1" ... textureeast "X2" }`
           -> our WALL{(N-1)*2} (light) / +1 (dark)
  doors    fixed table (DOOR1/2/3, SLOT, ELEV vs our WALL098..105,
           derived from WL_DRAW.C's DOORWALL layout)
  statics  xlat things {oldnum, Class} -> decorate Class sprite
           -> our S{oldnum-23:03d}
  weapons  ECWolf view sprites (V_KN etc) -> our W??? by role
  enemies  role-join: ECWolf decorate state labels vs our
           enemies.gen.zs state labels, same VSWAP order both sides

Usage: python tools/gen_hdmap.py <path-to-ecwolf.pk3>
"""
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# door/jamb/elevator faces: our converter's fixed layout (DOORWALL=98)
DOORS = {
    "DOOR1_1": "WALL098", "DOOR1_2": "WALL099",     # normal door
    "SLOT1_1": "WALL100", "SLOT1_2": "WALL101",     # jamb
    "ELEV1_1": "WALL102", "ELEV1_2": "WALL103",     # elevator door
    "DOOR3_1": "WALL104", "DOOR3_2": "WALL105",     # locked
    # ELEV2/DOOR2: elevator switch walls handled via tile table
}

# ECWolf view-weapon sprite names -> ours (same frame letters, same
# VSWAP order: READY,ATK1..4 = A..E). These are the ECWolf-side sprite
# NAMES, not the HD pack's file names: the pack maps its own art onto
# these through its TEXTURES lump (Sprite PISGA0 { Patch V_LUGR_A }),
# so the converter reads the frame->art join from the pack itself
# rather than guessing it from filenames.
WEAPONS = {"KNIF": "WKNF", "PISG": "WPIS", "MCHG": "WMGN", "CHGG": "WCHN"}


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: gen_hdmap.py <ecwolf.pk3>")
    z = zipfile.ZipFile(sys.argv[1])
    xlat = z.read("xlat/wolf3d.txt").decode("latin-1")

    out = {"walls": {}, "sprites": {}, "weapons": dict(WEAPONS)}
    out["walls"].update(DOORS)

    # ---- walls ----------------------------------------------------------
    for m in re.finditer(
            r'tile\s+(\d+)\s*\{\s*'
            r'texturenorth\s*=\s*"(\w+)";\s*texturesouth\s*=\s*"\w+";\s*'
            r'textureeast\s*=\s*"(\w+)"', xlat):
        code = int(m.group(1))
        if code > 64:
            continue                    # 65+ are door/special codes
        out["walls"][m.group(2)] = f"WALL{(code - 1) * 2:03d}"
        out["walls"][m.group(3)] = f"WALL{(code - 1) * 2 + 1:03d}"

    # ---- statics via things + decorate ---------------------------------
    things = {}
    for m in re.finditer(r'\{(\d+),\s*\$?(\w+),\s*\d+,\s*\d+,\s*\d+\}',
                         xlat):
        things[m.group(2)] = int(m.group(1))

    # class -> spawn sprite from all wolf decorate files
    dec = ""
    for n in z.namelist():
        if n.startswith("actors/wolf/") and n.endswith(".txt"):
            dec += z.read(n).decode("latin-1") + "\n"
    spawn_sprite = {}
    for m in re.finditer(
            r'actor\s+(\w+)(?:\s*:\s*(\w+))?[^{]*\{(.*?)\n\}',
            dec, re.S):
        cname, parent, body = m.group(1), m.group(2), m.group(3)
        sm = re.search(r'[Ss]pawn:\s*\n?\s*(\w{4})\s', body)
        if sm:
            spawn_sprite[cname] = sm.group(1)

    for cname, oldnum in things.items():
        spr = spawn_sprite.get(cname)
        if not spr or oldnum < 23:
            continue
        idx = oldnum - 23
        if 0 <= idx <= 70:
            out["sprites"][spr] = f"S{idx:03d}"

    Path(ROOT / "docs/data/hdpack_map.json").write_text(
        json.dumps(out, indent=1, sort_keys=True) + "\n")
    print(f"walls {len(out['walls'])}, statics {len(out['sprites'])}, "
          f"weapons {len(out['weapons'])}")


if __name__ == "__main__":
    main()
