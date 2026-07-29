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
          "T_Ghosts": 12, "T_DogChase": 13, "A_HitlerMorph": 14,
          "T_Schabb": 20, "T_Gift": 21, "T_Fat": 22, "T_Fake": 23,
          "T_SchabbThrow": 24, "T_GiftThrow": 25, "T_FakeFire": 26,
          "T_Projectile": 27, "A_Smoke": 28, "A_MechaSound": 29,
          "A_Slurpie": 30, "T_Launch": 31, "A_Relaunch": 32,
          # Spear: T_Will is the shared boss chase for Wilhelm, the
          # Angel and the Death Knight; A_Dormant is the Spectre's wait
          "T_Will": 33, "T_UShoot": 34, "A_Victory": 35,
          "A_StartAttack": 36, "A_Dormant": 37, "A_Breathing": 38}

# Sprite naming is mechanical across every enemy: the source's SPR_<X>_<suffix>
# suffixes map to a 3-char base + category letter (S stand, W walk, P pain,
# A attack, D die/dead, J jump) with frames in suffix order.
ENEMIES = {
    "Guard":   {"table": "WolfGuardTable", "prefix": "SPR_GRD_", "base": "GRD"},
    "Dog":     {"table": "WolfDogTable",   "prefix": "SPR_DOG_", "base": "DOG"},
    "Officer": {"table": "WolfOfficerTable", "prefix": "SPR_OFC_", "base": "OFC"},
    "SS":      {"table": "WolfSSTable",    "prefix": "SPR_SS_",  "base": "SSG"},
    "Mutant":  {"table": "WolfMutantTable", "prefix": "SPR_MUT_", "base": "MUT"},
    # bosses: single-view (rotate=false), suffixes W1/DIE1/SHOOT1 style
    "Hans":    {"table": "WolfHansTable",    "prefix": "SPR_BOSS_",   "base": "BOS"},
    "Gretel":  {"table": "WolfGretelTable",  "prefix": "SPR_GRETEL_", "base": "GRE"},
    "Schabbs": {"table": "WolfSchabbsTable", "prefix": "SPR_SCHABB_", "base": "SCH"},
    "Gift":    {"table": "WolfGiftTable",    "prefix": "SPR_GIFT_",   "base": "GIF"},
    "Fat":     {"table": "WolfFatTable",     "prefix": "SPR_FAT_",    "base": "FTB"},
    "Fake":    {"table": "WolfFakeTable",    "prefix": "SPR_FAKE_",   "base": "FAK"},
    "Mecha":   {"table": "WolfMechaTable",   "prefix": "SPR_MECHA_",  "base": "MEC"},
    "Hitler":  {"table": "WolfHitlerTable",  "prefix": "SPR_HITLER_", "base": "HIT"},
    # Spear of Destiny bosses (SPEAR-only sprite enum entries; the state
    # tables are shared zscript, the chunk mapping is per-set)
    "Trans":   {"table": "WolfTransTable",   "prefix": "SPR_TRANS_",   "base": "TRN"},
    "Will":    {"table": "WolfWillTable",    "prefix": "SPR_WILL_",    "base": "WIL"},
    "Uber":    {"table": "WolfUberTable",    "prefix": "SPR_UBER_",    "base": "UBR"},
    "Death":   {"table": "WolfDeathTable",   "prefix": "SPR_DEATH_",   "base": "DKN"},
    "Angel":   {"table": "WolfAngelTable",   "prefix": "SPR_ANGEL_",   "base": "ANG"},
    "Spectre": {"table": "WolfSpectreTable", "prefix": "SPR_SPECTRE_", "base": "SPC"},
}
STATE_PREFIX = {"Guard": "s_grd", "Dog": "s_dog", "Officer": "s_ofc",
                "SS": "s_ss", "Mutant": "s_mut",
                "Hans": "s_boss", "Gretel": "s_gretel", "Schabbs": "s_schabb",
                "Gift": "s_gift", "Fat": "s_fat", "Fake": "s_fake",
                "Mecha": "s_mecha", "Hitler": "s_hitler",
           "Trans": "s_trans", "Will": "s_will", "Uber": "s_uber",
           "Death": "s_death", "Angel": "s_angel", "Spectre": "s_spectre"}
# state order per enemy: stand, path, pain, shoot, chase, die (source order)
# NOTE: "dead" is its own group - the dog's final state is s_dogdead,
# not s_dogdie4, and omitting it truncated the death chain.
STATE_ORDER = ["stand", "path", "pain", "shoot", "chase", "die",
               "dead", "jump", "deathcam",
               # Spear additions: the Spectre idles in a wait loop and
               # wakes through its own state; the Angel recharges tired
               "wait", "wake", "tired"]


def classify(suffix, seen):
    """SPR suffix -> (category letter, frame index). seen tracks per-category
    ordering so frames follow the source's numbering."""
    if suffix == "S_1":
        return "S", 0, "rot8"
    m = re.match(r"W(\d)_1$", suffix)
    if m:
        return "W", int(m.group(1)) - 1, "rot8"
    m = re.match(r"PAIN_(\d)$", suffix)
    if m:
        return "P", int(m.group(1)) - 1, "pain"
    m = re.match(r"SHOOT(\d)$", suffix)
    if m:
        return "A", int(m.group(1)) - 1, "flat"
    m = re.match(r"JUMP(\d)$", suffix)
    if m:
        return "J", int(m.group(1)) - 1, "flat"
    m = re.match(r"DIE_?(\d)$", suffix)
    if m:
        return "D", int(m.group(1)) - 1, "flat"
    m = re.match(r"W(\d)$", suffix)          # boss walk (no rotations)
    if m:
        return "W", int(m.group(1)) - 1, "flat"
    m = re.match(r"TIRED(\d)$", suffix)      # Angel of Death recharge
    if m:
        return "T", int(m.group(1)) - 1, "flat"
    m = re.match(r"F(\d)$", suffix)          # Spectre fade/wake frames
    if m:
        return "F", int(m.group(1)) - 1, "flat"
    if suffix == "SHOOT":                    # fake Hitler: single frame
        return "A", 0, "flat"
    if suffix == "DEAD":
        return "D", seen.get("D", 0), "flat"
    raise SystemExit(f"unclassified sprite suffix: {suffix}")


def build_enemy_cfg(name, cfg, states):
    """Derive the state list (source order) and sprite map for one enemy."""
    pre = STATE_PREFIX[name]
    ordered = []
    for group in STATE_ORDER:
        g = sorted([n for n in states
                    if n.startswith(pre + group)],
                   key=lambda n: (len(n), n))
        ordered += g
    if not ordered:
        raise SystemExit(f"no states for {name}")
    sprites, seen = {}, {}
    for n in ordered:
        spr = states[n]["sprite"]
        if spr in sprites:
            continue
        suffix = spr[len(cfg["prefix"]):]
        cat, idx, kind = classify(suffix, seen)
        seen[cat] = max(seen.get(cat, 0), idx + 1)
        sprites[spr] = (cfg["base"] + cat, chr(65 + idx), kind)
    return ordered, sprites


DOOMEDS = ['    21001 = "WolfGuardStand"',
           '    21002 = "WolfGuardPatrol"',
           '    21003 = "WolfOfficerStand"',
           '    21004 = "WolfOfficerPatrol"',
           '    21005 = "WolfSSStand"',
           '    21006 = "WolfSSPatrol"',
           '    21007 = "WolfDogStand"',
           '    21008 = "WolfDogPatrol"',
           '    21009 = "WolfMutantStand"',
           '    21010 = "WolfMutantPatrol"',
           '    21020 = "WolfHans"',
           '    21021 = "WolfGretel"',
           '    21022 = "WolfGift"',
           '    21023 = "WolfFat"',
           '    21024 = "WolfSchabbs"',
           '    21025 = "WolfFakeHitler"',
           '    21026 = "WolfMechaHitler"',
           # Spear of Destiny
           '    21030 = "WolfSpectre"',
           '    21031 = "WolfAngel"',
           '    21032 = "WolfTrans"',
           '    21033 = "WolfUber"',
           '    21034 = "WolfWill"',
           '    21035 = "WolfDeathKnight"']


def sprite_enum(spear=False):
    """The sprite_t enum as the given build sees it.

    The two builds enumerate DIFFERENT sprite sets, so the same lump
    name resolves to different VSWAP chunks per game - which is exactly
    why the chunk->lump copy list is emitted once per set while the
    ZScript tables (lump names only) stay shared.
    """
    text = (SRC / "WL_DEF.H").read_text(errors="replace")
    start = text.find("SPR_DEMO")
    lines = text[start:text.find("}", start)].splitlines()
    names, stack = [], []
    for ln in lines:
        s = ln.strip()
        if s.startswith("#ifdef"):
            stack.append(s.split()[1] == "SPEAR" and spear)
            continue
        if s.startswith("#ifndef"):
            stack.append(not (s.split()[1] == "SPEAR" and spear))
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
            # Match EVERY enum identifier, not just SPR_-prefixed
            # ones: id's header has a typo - MACHINEGUNATK3 lost
            # its SPR_ prefix - and an SPR_-only regex silently
            # DROPPED that slot, shifting every later index down
            # by one. That is why Spear's chaingun wore a machine
            # gun. Cross-check: the parsed length must equal the
            # VSWAP sprite count (it was short by exactly one).
            body = ln.split("//")[0]
            names += [m for m in re.findall(r"[A-Z][A-Z0-9_]{2,}", body)
                      if not m.startswith(("NUM", "START", "STRUCT"))]
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
    specs = []
    regs = {}       # per enemy: sprite name -> set of frame chars (for zs regs)

    for ename, cfg in ENEMIES.items():
        state_list, cfg_sprites = build_enemy_cfg(ename, cfg, states)
        cfg = dict(cfg, sprites=cfg_sprites, states=state_list)
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

        # sprite copy SPECS: resolved against each build's enum below,
        # since the same lump sits at different chunks per game
        for sprkey, (sprname, frame, kind) in cfg["sprites"].items():
            specs.append((sprkey, sprname, frame, kind))

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

    # Non-enemy sprites whose actors use plain ZScript states. Resolved
    # BY NAME per build rather than hardcoded chunk numbers - the Spear
    # enum shifts everything, and its own extras (the Angel's spark, the
    # Death Knight's rocket) only exist there.
    EXTRAS = [("SPR_HYPO1", "HYPOA0"), ("SPR_HYPO2", "HYPOB0"),
              ("SPR_HYPO3", "HYPOC0"), ("SPR_HYPO4", "HYPOD0"),
              ("SPR_ROCKET_1", "MISLA0"),
              ("SPR_FIRE1", "FIREA0"), ("SPR_FIRE2", "FIREB0"),
              ("SPR_BJ_W1", "BJRNA0"), ("SPR_BJ_W2", "BJRNB0"),
              ("SPR_BJ_W3", "BJRNC0"), ("SPR_BJ_W4", "BJRND0"),
              ("SPR_BJ_JUMP1", "BJJPA0"), ("SPR_BJ_JUMP2", "BJJPB0"),
              ("SPR_BJ_JUMP3", "BJJPC0"), ("SPR_BJ_JUMP4", "BJJPD0"),
              # E3 secret floor ghosts (WL6 only)
              ("SPR_BLINKY_W1", "BLKYA0"), ("SPR_BLINKY_W2", "BLKYB0"),
              ("SPR_PINKY_W1", "PNKYA0"), ("SPR_PINKY_W2", "PNKYB0"),
              ("SPR_CLYDE_W1", "CLYDA0"), ("SPR_CLYDE_W2", "CLYDB0"),
              ("SPR_INKY_W1", "INKYA0"), ("SPR_INKY_W2", "INKYB0"),
              # Spear only: Angel spark, Death Knight heat-seeker
              ("SPR_SPARK1", "SPRKA0"), ("SPR_SPARK2", "SPRKB0"),
              ("SPR_SPARK3", "SPRKC0"), ("SPR_SPARK4", "SPRKD0"),
              ("SPR_HROCKET_1", "HMISA0")]

    def copies_for(en):
        """chunk -> lump for ONE build; entries the build lacks are
        simply absent (SOD bosses in WL6, the ghosts in Spear)."""
        out, seen = [], set()
        for sprkey, sprname, frame, kind in specs:
            if sprkey not in en:
                continue
            base = en[sprkey]
            if kind == "rot8":
                pairs = [(base + r, f"{sprname}{frame}{r + 1}")
                         for r in range(8)]
            elif kind == "pain":
                # CalcRotate rotate==2: +0 (rots 1-4) / +4 (rots 5-8)
                pairs = [(base, f"{sprname}{frame}{r}") for r in range(1, 5)]
                pairs += [(base + 4, f"{sprname}{frame}{r}")
                          for r in range(5, 9)]
            else:
                pairs = [(base, f"{sprname}{frame}0")]
            for chunk, lump in pairs:
                if lump not in seen:
                    seen.add(lump)
                    out.append([chunk, lump])
        for sprkey, lump in EXTRAS:
            if sprkey in en and lump not in seen:
                seen.add(lump)
                out.append([en[sprkey], lump])
        return out

    all_lumps = set()
    for setname, en in (("wl6", enum), ("sod", sprite_enum(spear=True))):
        cp = copies_for(en)
        all_lumps.update(l for _, l in cp)
        (ROOT / "docs" / "data" / f"sprite_copies_{setname}.json").write_text(
            json.dumps({"note": f"chunk -> sprite lump ({setname}, "
                                "gen_enemies.py)", "copies": cp}, indent=1))
        print(f"  {setname}: {len(cp)} sprite lumps")

    # placeholders so the IPK3 boots before any user data is extracted
    ph = placeholder_png()
    for lump in sorted(all_lumps):
        (ROOT / "src" / "sprites" / f"{lump}.png").write_bytes(ph)

    print(f"generated {len(ENEMIES)} enemies, {len(all_lumps)} sprite lumps")


if __name__ == "__main__":
    main()
