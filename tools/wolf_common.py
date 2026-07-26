#!/usr/bin/env python3
"""Shared helpers for the Wolf3D extraction pipeline.

Data files are user-supplied (never committed): looked up in gamedata/ first,
then the local Steam install. WL6 = registered Wolfenstein 3D; SOD = Spear
(base/m1 in the Steam layout).

Decoders (Carmack / RLEW / Huffman) are the id engine family shared with the
Catacomb pipeline (F:\\CatacombDoom tools) — same algorithms, ID_CA.C lineage.

Semantic tables implement the charter (docs/FIDELITY_CHARTER.md):
  plane 0: walls < 107 (AREATILE); doors 90-101 (DOOR-*); ambush 106 (TILE-003);
           area floors 107+ (TILE-001)
  plane 1: MAP-001..016 spawn codes incl. difficulty tiers (+36; mutants +18)
"""
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAMEDATA = ROOT / "gamedata"
STEAM_BASE = Path(r"F:\SteamLibrary\steamapps\common\Wolfenstein 3D\base")

RLEW_DEFAULT = 0xABCD
AREATILE = 107
AMBUSHTILE = 106
EXITTILE = 99  # wall texture code for exit-elevator side rails
ELEVATORTILE = 21
NUMAREAS = 37


def find_data(ext: str):
    """Return dict of {NAME: Path} for all files with the given extension."""
    hits = {}
    for base in (GAMEDATA, GAMEDATA / "m1", STEAM_BASE, STEAM_BASE / "m1"):
        if base.is_dir():
            for p in base.glob(f"*.{ext}"):
                hits.setdefault(p.stem.upper(), p)
    return hits


def carmack_expand(data, expanded_words):
    """Undo Carmackization (near 0xA7 / far 0xA8 pointer copies). Word stream."""
    NEAR, FAR = 0xA7, 0xA8
    out = []
    i = 0
    while len(out) < expanded_words:
        count = data[i]
        tag = data[i + 1]
        if tag == NEAR and count == 0:            # escape: literal word
            out.append(data[i + 2] | (tag << 8))
            i += 3
        elif tag == FAR and count == 0:
            out.append(data[i + 2] | (tag << 8))
            i += 3
        elif tag == NEAR:
            offset = data[i + 2]
            start = len(out) - offset
            for j in range(count):
                out.append(out[start + j])
            i += 3
        elif tag == FAR:
            offset = data[i + 2] | (data[i + 3] << 8)
            for j in range(count):
                out.append(out[offset + j])
            i += 4
        else:
            out.append(data[i] | (data[i + 1] << 8))
            i += 2
    return out[:expanded_words]


def rlew_expand(words, rlew_tag, expanded_words):
    """Undo RLEW run-length on `rlew_tag`. Input/output are u16 word lists."""
    out = []
    i = 0
    while len(out) < expanded_words and i < len(words):
        w = words[i]
        if w == rlew_tag:
            count = words[i + 1]
            value = words[i + 2]
            out.extend([value] * count)
            i += 3
        else:
            out.append(w)
            i += 1
    return out[:expanded_words]


def huff_expand(nodes, data, expanded_len):
    """Huffman-expand `data` to `expanded_len` bytes. Root node = 254."""
    out = bytearray()
    node = 254
    for byte in data:
        for bit in range(8):
            val = nodes[node][(byte >> bit) & 1]
            if val < 256:
                out.append(val)
                node = 254
                if len(out) == expanded_len:
                    return bytes(out)
            else:
                node = val - 256
    return bytes(out)


def load_maphead(path: Path):
    """MAPHEAD file: u16 RLEW tag + up to 100 i32 chunk offsets (ID_CA.C)."""
    data = path.read_bytes()
    (tag,) = struct.unpack_from("<H", data, 0)
    n = min(100, (len(data) - 2) // 4)
    offsets = struct.unpack_from(f"<{n}i", data, 2)
    return tag, [o for o in offsets]


# ---------------------------------------------------------------------------
# plane 0 (walls/doors/areas) semantics — charter TILE-*, DOOR-*
# ---------------------------------------------------------------------------

DOOR_LOCKS = {0: "normal", 1: "gold", 2: "silver", 3: "lock3", 4: "lock4",
              5: "elevator"}


def wall_meaning(v):
    """Return semantic dict for a plane-0 value, or None for plain floor."""
    if 90 <= v <= 101:
        return {"kind": "door", "vertical": (v % 2 == 0),
                "lock": DOOR_LOCKS[(v - 90) // 2], "code": v}
    if v == AMBUSHTILE:
        return {"kind": "ambush_floor", "code": v}
    if v >= AREATILE:
        return {"kind": "floor", "area": v - AREATILE,
                "secret_exit_pad": v == 107, "code": v}
    m = {"kind": "wall", "code": v}
    if v == ELEVATORTILE:
        m["kind"] = "elevator_switch"
    elif v == EXITTILE:
        m["kind"] = "exit_rail"
    return m


# ---------------------------------------------------------------------------
# plane 1 (objects) semantics — charter MAP-001..016
# gd enum: baby=0 easy=1 medium=2 hard=3; min_skill 0 = always spawns
# dirtype order (WL_DEF.H): east,NE,north,NW,west,SW,south,SE
# ---------------------------------------------------------------------------

DIR4 = ["north", "east", "south", "west"]         # starts/enemies: tile-base
DIR8 = ["east", "northeast", "north", "northwest",
        "west", "southwest", "south", "southeast"]  # turn arrows 90-97

_ENEMY_RANGES = []  # (base, enemy, mode, tier_step)
for base, enemy, mode in ((108, "guard", "stand"), (112, "guard", "patrol"),
                          (116, "officer", "stand"), (120, "officer", "patrol"),
                          (126, "ss", "stand"), (130, "ss", "patrol"),
                          (134, "dog", "stand"), (138, "dog", "patrol")):
    _ENEMY_RANGES.append((base, enemy, mode, 36))
for base, enemy, mode in ((216, "mutant", "stand"), (220, "mutant", "patrol")):
    _ENEMY_RANGES.append((base, enemy, mode, 18))

BOSSES_WL6 = {214: "hans", 197: "gretel", 215: "gift", 179: "fat",
              196: "schabbs", 160: "fake_hitler", 178: "hitler"}
GHOSTS = {224: "blinky", 225: "clyde", 226: "pinky", 227: "inky"}
SOD_SPECIALS = {106: "spectre", 107: "angel", 125: "trans", 142: "uber",
                143: "will", 161: "death_knight"}


def object_meaning(v, sod: bool):
    """Return semantic dict for a plane-1 value, None for empty, or
    {'kind':'unknown'} for codes the charter doesn't cover (fail loudly)."""
    if v == 0:
        return None
    if 19 <= v <= 22:
        return {"kind": "player_start", "dir": DIR4[v - 19]}
    if 23 <= v <= 74:
        return {"kind": "static", "index": v - 23}
    if 90 <= v <= 97:
        return {"kind": "turn", "dir": DIR8[v - 90]}
    if v == 98:
        return {"kind": "pushwall"}
    if v == 99:
        # EXITTILE in plane 1: walking onto it fires VictoryTile() -> BJ
        # victory sequence (WL_AGENT.C:961, charter MAP-017)
        return {"kind": "victory_trigger"}
    if v == 124:
        return {"kind": "dead_guard"}
    if sod and v in SOD_SPECIALS:
        return {"kind": "boss", "enemy": SOD_SPECIALS[v]}
    if not sod and v in BOSSES_WL6:
        return {"kind": "boss", "enemy": BOSSES_WL6[v]}
    if not sod and v in GHOSTS:
        return {"kind": "ghost", "enemy": GHOSTS[v]}
    for base, enemy, mode, step in _ENEMY_RANGES:
        for tier, min_skill in ((0, 0), (1, 2), (2, 3)):
            lo = base + tier * step
            if lo <= v <= lo + 3:
                return {"kind": "enemy", "enemy": enemy, "mode": mode,
                        "dir": DIR4[v - lo], "min_skill": min_skill}
    return {"kind": "unknown", "code": v}


def omf_extract(path):
    """Return the raw bytes of the data segment stored in a MakeOBJ .OBJ.

    Walks OMF records and reconstructs the segment from LEDATA (0xA0) records,
    placing each record's payload at its enumerated data offset. (Shared with
    the Catacomb pipeline; GAMEPAL.OBJ/SIGNON.OBJ use only LEDATA.)
    """
    d = path.read_bytes()
    seg = bytearray()
    i = 0
    while i < len(d):
        rectype = d[i]
        (reclen,) = struct.unpack_from("<H", d, i + 1)
        body = d[i + 3:i + 3 + reclen]           # includes trailing checksum byte
        content = body[:-1]
        if rectype in (0xA0, 0xA1):               # LEDATA (16-/32-bit)
            if rectype == 0xA0:
                (offset,) = struct.unpack_from("<H", content, 1)
                data = content[3:]
            else:
                (offset,) = struct.unpack_from("<I", content, 1)
                data = content[5:]
            end = offset + len(data)
            if end > len(seg):
                seg.extend(b"\x00" * (end - len(seg)))
            seg[offset:end] = data
        elif rectype in (0xA2, 0xA3):
            raise NotImplementedError(f"LIDATA in {path.name} unsupported")
        i += 3 + reclen
    return bytes(seg)


def load_palette():
    """Wolf VGA palette from the source release's GAMEPAL.OBJ: 256 RGB
    triplets, 6-bit VGA scaled to 8-bit (<<2 | >>4 per VGA convention)."""
    raw = omf_extract(ROOT / "reference" / "wolfsrc" / "WOLFSRC" / "OBJ" / "GAMEPAL.OBJ")
    assert len(raw) >= 768, f"GAMEPAL segment too short: {len(raw)}"
    pal = []
    for i in range(256):
        r, g, b = raw[i * 3:i * 3 + 3]
        pal.append(((r << 2) | (r >> 4), (g << 2) | (g >> 4), (b << 2) | (b >> 4)))
    return pal
