#!/usr/bin/env python3
"""Generate enemy state tables + sprite plumbing from docs/data/state_tables.json.

This IS the ledger's state-table diff made literal: the generated ZScript
arrays are the source's statetype rows, one to one. The WolfEnemySim
interpreter (enemies.zs) executes them at Wolf-tic fidelity.

Per-enemy extension = an ENEMIES entry (sprite mapping + state list);
the interpreter is shared.

Outputs (generated, never hand-edit):
  src/zscript/enemies.gen.zs      state tables + state-index constants
  src/mapinfo_enemies.txt         DoomEdNums include
  src/sprites/*.png               placeholders (make_assets overrides)
  docs/data/sprite_copies.json    chunk->lump copy list for make_assets
"""
import json
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"

THINKS = {"None": 0, "T_Stand": 1, "T_Path": 2, "T_Chase": 3, "T_Shoot": 4,
          "T_Bite": 5, "A_DeathScream": 10, "A_StartDeathCam": 11,
          "T_Ghosts": 12, "T_DogChase": 13, "A_HitlerMorph": 14}

ENEMIES = {
    "Guard": {
        "table": "WolfGuardTable",
        # SPR_* -> (doom sprite, frame char, kind: rot8|flat|pain)
        "sprites": {
            "SPR_GRD_S_1":    ("GRDS", "A", "rot8"),
            "SPR_GRD_W1_1":   ("GRDW", "A", "rot8"),
            "SPR_GRD_W2_1":   ("GRDW", "B", "rot8"),
            "SPR_GRD_W3_1":   ("GRDW", "C", "rot8"),
            "SPR_GRD_W4_1":   ("GRDW", "D", "rot8"),
            "SPR_GRD_PAIN_1": ("GRDP", "A", "pain"),
            "SPR_GRD_PAIN_2": ("GRDP", "B", "pain"),
            "SPR_GRD_DIE_1":  ("GRDD", "A", "flat"),
            "SPR_GRD_DIE_2":  ("GRDD", "B", "flat"),
            "SPR_GRD_DIE_3":  ("GRDD", "C", "flat"),
            "SPR_GRD_DEAD":   ("SDED", "A", "flat"),
            "SPR_GRD_SHOOT1": ("GRDA", "A", "flat"),
            "SPR_GRD_SHOOT2": ("GRDA", "B", "flat"),
            "SPR_GRD_SHOOT3": ("GRDA", "C", "flat"),
        },
        "states": ["s_grdstand",
                   "s_grdpath1", "s_grdpath1s", "s_grdpath2", "s_grdpath3",
                   "s_grdpath3s", "s_grdpath4",
                   "s_grdpain", "s_grdpain1",
                   "s_grdshoot1", "s_grdshoot2", "s_grdshoot3",
                   "s_grdchase1", "s_grdchase1s", "s_grdchase2",
                   "s_grdchase3", "s_grdchase3s", "s_grdchase4",
                   "s_grddie1", "s_grddie2", "s_grddie3", "s_grddie4"],
    },
    "Dog": {
        "table": "WolfDogTable",
        "sprites": {
            "SPR_DOG_W1_1":  ("DOGW", "A", "rot8"),
            "SPR_DOG_W2_1":  ("DOGW", "B", "rot8"),
            "SPR_DOG_W3_1":  ("DOGW", "C", "rot8"),
            "SPR_DOG_W4_1":  ("DOGW", "D", "rot8"),
            "SPR_DOG_JUMP1": ("DOGJ", "A", "flat"),
            "SPR_DOG_JUMP2": ("DOGJ", "B", "flat"),
            "SPR_DOG_JUMP3": ("DOGJ", "C", "flat"),
            "SPR_DOG_DIE_1": ("DOGD", "A", "flat"),
            "SPR_DOG_DIE_2": ("DOGD", "B", "flat"),
            "SPR_DOG_DIE_3": ("DOGD", "C", "flat"),
            "SPR_DOG_DEAD":  ("DOGD", "D", "flat"),
        },
        "states": ["s_dogpath1", "s_dogpath1s", "s_dogpath2", "s_dogpath3",
                   "s_dogpath3s", "s_dogpath4",
                   "s_dogjump1", "s_dogjump2", "s_dogjump3", "s_dogjump4",
                   "s_dogjump5",
                   "s_dogchase1", "s_dogchase1s", "s_dogchase2",
                   "s_dogchase3", "s_dogchase3s", "s_dogchase4",
                   "s_dogdie1", "s_dogdie2", "s_dogdie3", "s_dogdead"],
    },
}

DOOMEDS = ['    21001 = "WolfGuardStand"',
           '    21002 = "WolfGuardPatrol"',
           '    21007 = "WolfDogStand"',
           '    21008 = "WolfDogPatrol"']


def sprite_enum():
    text = (SRC / "WL_DEF.H").read_text(errors="replace")
    start = text.find("SPR_DEMO")
    lines = text[start:text.find("}", start)].splitlines()
    names, stack = [], []
    for ln in lines:
        s = ln.strip()
        if s.startswith("#ifdef"):
            stack.append(False)
            continue
        if s.startswith("#ifndef"):
            stack.append(s.split()[1] == "SPEAR")
            continue
        if s.startswith("#else"):
            if stack:
                stack[-1] = not stack[-1]
            continue
        if s.startswith("#endif"):
            if stack:
                stack.pop()
            continue
        if all(stack):
            names += re.findall(r"\b(SPR_[A-Z0-9_]+)\b", ln)
    return {n: i for i, n in enumerate(names)}


def placeholder_png():
    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload)))
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    idat = zlib.compress(b"\x00\x00\x00\x00\x00")
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"grAb", struct.pack(">ii", 0, 0))
            + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def main():
    states = {s["name"]: s for s in json.loads(
        (ROOT / "docs" / "data" / "state_tables.json").read_text())["states"]}
    enum = sprite_enum()

    zs = ["// GENERATED by tools/gen_enemies.py from docs/data/state_tables.json",
          "// Rows are WL_ACT2.C statetype entries, one to one. Do not edit.",
          ""]
    copies = []
    seen_lumps = set()
    regs = {}       # per enemy: sprite name -> set of frame chars (for zs regs)

    for ename, cfg in ENEMIES.items():
        state_list = cfg["states"]
        idx_of = {n: i for i, n in enumerate(state_list)}
        rot_l, spr_l, frm_l, tic_l, thk_l, act_l, nxt_l = ([] for _ in range(7))
        consts = []
        reg = {}
        for name in state_list:
            st = states[name]
            sprname, frame, kind = cfg["sprites"][st["sprite"]]
            rot_l.append({"true": 1, "false": 0, "1": 1, "2": 2}[st["rotate"]])
            spr_l.append(sprname)
            frm_l.append(ord(frame) - 65)
            tic_l.append(int(st["tics"]))
            thk_l.append(THINKS[st["think"] or "None"])
            act_l.append(THINKS[st["action"] or "None"])
            nxt = st["next"]
            nxt_l.append(idx_of.get(nxt, -1) if nxt else -1)
            consts.append(f"    const {name[2:].upper()} = {idx_of[name]};")
            reg.setdefault(sprname, set()).add(frame)

        def arr(aname, vals, quote=False):
            items = ", ".join(f'"{v}"' if quote else str(v) for v in vals)
            t = "String" if quote else "int"
            return f"    static const {t} {aname}[] = {{ {items} }};"

        zs += [f"class {cfg['table']}", "{"] + consts + [
            arr("ROT", rot_l), arr("SPR", spr_l, True), arr("FRM", frm_l),
            arr("TICS", tic_l), arr("THINK", thk_l), arr("ACT", act_l),
            arr("NEXT", nxt_l), "}", ""]
        regs[ename] = reg

        # sprite copy list
        for sprkey, (sprname, frame, kind) in cfg["sprites"].items():
            base = enum[sprkey]
            if kind == "rot8":
                for r in range(8):
                    copies.append([base + r, f"{sprname}{frame}{r + 1}"])
            elif kind == "pain":
                # CalcRotate rotate==2: +0 (rots 1-4 approx) / +4 (rots 5-8)
                for r in range(1, 5):
                    copies.append([base, f"{sprname}{frame}{r}"])
                for r in range(5, 9):
                    copies.append([base + 4, f"{sprname}{frame}{r}"])
            else:
                copies.append([base, f"{sprname}{frame}0"])

    # sprite-name registration states (engine needs States blocks to
    # create sprite entries; see the SpriteRegistry pattern)
    zs += ["// sprite-name registration only — never entered",
           "class WolfSpriteRegistry : Actor", "{", "    States", "    {",
           "    Reg:"]
    allreg = {}
    for reg in regs.values():
        for spr, frames in reg.items():
            allreg.setdefault(spr, set()).update(frames)
    for spr, frames in sorted(allreg.items()):
        zs.append(f"        {spr} {''.join(sorted(frames))} -1;")
    zs += ["        Stop;", "    }", "}", ""]

    (ROOT / "src" / "zscript" / "enemies.gen.zs").write_text("\n".join(zs) + "\n")
    (ROOT / "src" / "mapinfo_enemies.txt").write_text(
        "// GENERATED by tools/gen_enemies.py — included from MAPINFO\n"
        "DoomEdNums\n{\n" + "\n".join(DOOMEDS) + "\n}\n")

    dedup = []
    for c in copies:
        if c[1] not in seen_lumps:
            seen_lumps.add(c[1])
            dedup.append(c)
    (ROOT / "docs" / "data" / "sprite_copies.json").write_text(
        json.dumps({"note": "chunk -> sprite lump (gen_enemies.py)",
                    "copies": dedup}, indent=1))
    ph = placeholder_png()
    for _, lump in dedup:
        (ROOT / "src" / "sprites" / f"{lump}.png").write_bytes(ph)

    print(f"generated {len(ENEMIES)} enemies, {len(dedup)} sprite lumps")


if __name__ == "__main__":
    main()
