#!/usr/bin/env python3
"""Coverage Ledger inventory tool (Phase 0.5).

Mechanically enumerates every function definition, #define, and statetype entry
across WOLFSRC, applies the classification map, and reports the unclassified
count. Exhaustiveness rule: unclassified must reach zero.

Usage: python tools/ledger.py [--write]
  --write  regenerate docs/ledger/inventory.json and docs/ledger/SUMMARY.md
Exit code 1 if any item is unclassified (so CI/harness can gate on it).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"
OUT = ROOT / "docs" / "ledger"

BUCKETS = {"game-behavior", "platform", "data-pipeline", "presentation", "dead-debug"}

# File-level default classification. Symbol-level overrides below win.
FILE_DEFAULTS = {
    # Gameplay simulation — ported from source, every constant chartered.
    "WL_ACT1.C": "game-behavior",   # doors, pushwalls, statics, areas
    "WL_ACT2.C": "game-behavior",   # enemy actors, state tables, projectiles
    "WL_AGENT.C": "game-behavior",  # player: movement, weapons, pickups
    "WL_STATE.C": "game-behavior",  # AI framework: sight, damage, pathing
    "WL_PLAY.C": "game-behavior",   # play loop, input polling, palette flashes
    "WL_GAME.C": "game-behavior",   # level setup, spawn codes, death, elevators
    "WL_INTER.C": "game-behavior",  # intermission tally, bonuses
    "WL_MAIN.C": "game-behavior",   # game init defaults (mixed; overrides below)
    "WL_DEF.H": "game-behavior",    # the constants header
    "WL_ASM.ASM": "platform",
    # Presentation — recreated per launcher philosophy.
    "WL_MENU.C": "presentation",
    "WL_MENU.H": "presentation",
    "WL_TEXT.C": "presentation",
    # Debug/dead — deliberately omitted, documented.
    "WL_DEBUG.C": "dead-debug",
    "WOLFHACK.C": "dead-debug",
    # Renderer — replaced by UZDoom. NOTE: TransformActor sets FL_VISABLE which
    # combat math consumes; that contract is chartered as game-behavior (see
    # overrides), the rasterization is not.
    "WL_DRAW.C": "platform",
    "WL_SCALE.C": "platform",
    "WL_DR_A.ASM": "platform",
    # id engine libs.
    "ID_CA.C": "data-pipeline",     # CAL/Carmack/RLEW loaders -> extractor
    "ID_CA.H": "data-pipeline",
    "ID_VL.C": "platform", "ID_VL.H": "platform", "ID_VL_A.ASM": "platform",
    "ID_VH.C": "platform", "ID_VH.H": "platform",  # FizzleFade override below
    "ID_IN.C": "platform", "ID_IN.H": "platform",
    "ID_SD.C": "platform", "ID_SD.H": "platform", "ID_SDD.C": "platform",
    "ID_SD_A.ASM": "platform",
    "ID_MM.C": "platform", "ID_MM.H": "platform",
    "ID_PM.C": "platform", "ID_PM.H": "platform",
    "ID_US.H": "platform",
    "ID_US_1.C": "platform",
    "ID_US_A.ASM": "platform",      # rndtable override below
    "ID_HEADS.H": "platform",
    "ID_HEAD.H": "platform",
    "ID_VH_A.ASM": "platform",
    "OLDSCALE.C": "dead-debug",     # superseded scaler id left in the release
    "SDMVER.H": "data-pipeline",    # version-build configuration
    "SODVER.H": "data-pipeline",
    "WOLFVER.H": "data-pipeline",
    "SPANISH.H": "presentation",    # localized strings
    # Per-release build-config headers (registered/shareware/Japanese/GT etc.)
    "SPANVER.H": "data-pipeline",
    "WLFJ1VER.H": "data-pipeline",
    "WOLF1VER.H": "data-pipeline",
    "WOLFGTV.H": "data-pipeline",
    "WOLFJVER.H": "data-pipeline",
    "WHACK_A.ASM": "dead-debug",    # WOLFHACK companion asm
    "C0.ASM": "platform",
    "H_LDIV.ASM": "platform",
    "JABHACK.ASM": "platform",
    "CONTIGSC.C": "platform",
    "DETECT.C": "platform",
    "MUNGE.C": "platform",
    "SIGNON.ASM": "presentation",
    "VERSION.H": "data-pipeline",
    "FOREIGN.H": "presentation",
    "F_SPEAR.H": "presentation",
}
# Version/episode graphics + audio equate headers: generated data mappings.
GENERATED_HEADER_RE = re.compile(r"^(GFX|AUDIO|BUDIO).*\.(H|EQU)$")

# Symbol-level overrides: (file, symbol) -> bucket
OVERRIDES = {
    ("ID_VH.C", "FizzleFade"): "game-behavior",      # LFSR ported verbatim (FIZZ-001..004)
    ("ID_US_A.ASM", "rndtable"): "game-behavior",    # determinism source (RNG-001)
    ("ID_US_A.ASM", "US_RndT"): "game-behavior",
    ("ID_US_A.ASM", "US_InitRndT"): "game-behavior",
    ("WL_DRAW.C", "TransformActor"): "game-behavior",  # sets FL_VISABLE; combat consumes
}

FUNC_RE = re.compile(
    r"^(?:[A-Za-z_][A-Za-z0-9_]*[ \t]+)+\**([A-Za-z_][A-Za-z0-9_]*)[ \t]*\("
)
DEFINE_RE = re.compile(r"^#define[ \t]+([A-Za-z_][A-Za-z0-9_]*)")
STATE_RE = re.compile(r"^statetype[ \t]+(s_[A-Za-z0-9_]+)")
ASM_SYM_RE = re.compile(r"^(?:PUBLIC[ \t]+([A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*)[ \t]+PROC)", re.IGNORECASE)
CONTROL_KEYWORDS = {"if", "for", "while", "switch", "return", "else", "do", "sizeof", "asm"}


def scan_c(path: Path):
    funcs, defines, states = [], [], []
    lines = path.read_text(errors="replace").splitlines()
    for i, line in enumerate(lines):
        m = DEFINE_RE.match(line)
        if m:
            defines.append(m.group(1))
            continue
        m = STATE_RE.match(line)
        if m:
            states.append(m.group(1))
            continue
        m = FUNC_RE.match(line)
        if m and m.group(1) not in CONTROL_KEYWORDS and ";" not in line.split(")")[-1]:
            # id style: '{' on the same or a following non-blank line = definition
            rest = line.split(")", 1)[-1] if ")" in line else ""
            look = [rest] + lines[i + 1 : i + 3]
            joined = " ".join(look).strip()
            if joined.startswith("{") or joined == "" and False:
                funcs.append(m.group(1))
            elif "{" in joined.split(";")[0]:
                funcs.append(m.group(1))
    return funcs, defines, states


def scan_asm(path: Path):
    syms = []
    for line in path.read_text(errors="replace").splitlines():
        m = ASM_SYM_RE.match(line)
        if m:
            syms.append(m.group(1) or m.group(2))
    return syms


def classify(fname: str, symbol: str):
    if (fname, symbol) in OVERRIDES:
        return OVERRIDES[(fname, symbol)]
    if fname in FILE_DEFAULTS:
        return FILE_DEFAULTS[fname]
    if GENERATED_HEADER_RE.match(fname):
        return "data-pipeline"
    return None  # unclassified


def main():
    write = "--write" in sys.argv
    inventory = {}
    unclassified = []
    counts = {b: 0 for b in BUCKETS}
    total = 0

    for path in sorted(SRC.iterdir()):
        fname = path.name.upper()
        if path.suffix.upper() in (".C", ".H", ".EQU"):
            funcs, defines, states = scan_c(path)
            items = (
                [("func", f) for f in funcs]
                + [("define", d) for d in defines]
                + [("state", s) for s in states]
            )
        elif path.suffix.upper() == ".ASM":
            items = [("asmsym", s) for s in scan_asm(path)]
        else:
            continue
        entry = []
        for kind, sym in items:
            bucket = classify(fname, sym)
            entry.append({"kind": kind, "symbol": sym, "bucket": bucket})
            total += 1
            if bucket is None:
                unclassified.append(f"{fname}:{sym}")
            else:
                counts[bucket] += 1
        inventory[fname] = entry

    if write:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / "inventory.json").write_text(json.dumps(inventory, indent=1))
        lines = [
            "# Coverage Ledger — inventory summary\n",
            f"Generated by tools/ledger.py from reference/wolfsrc/WOLFSRC. Total items: {total}\n",
            "| Bucket | Count |", "|---|---|",
        ]
        for b in sorted(BUCKETS):
            lines.append(f"| {b} | {counts[b]} |")
        lines.append(f"| **unclassified** | **{len(unclassified)}** |")
        lines.append("\nPer-file counts:\n\n| File | Items | Bucket (default) |\n|---|---|---|")
        for fname, entry in inventory.items():
            default = FILE_DEFAULTS.get(fname) or (
                "data-pipeline" if GENERATED_HEADER_RE.match(fname) else "UNCLASSIFIED"
            )
            lines.append(f"| {fname} | {len(entry)} | {default} |")
        if unclassified:
            lines.append("\n## Unclassified (must reach zero)\n")
            lines += [f"- {u}" for u in unclassified]
        (OUT / "SUMMARY.md").write_text("\n".join(lines) + "\n")

    print(f"total={total} unclassified={len(unclassified)}")
    for b in sorted(BUCKETS):
        print(f"  {b}: {counts[b]}")
    if unclassified:
        print("UNCLASSIFIED:")
        for u in unclassified[:40]:
            print(f"  {u}")
        if len(unclassified) > 40:
            print(f"  ... and {len(unclassified)-40} more")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
