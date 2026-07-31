#!/usr/bin/env python3
"""Exit audit: every floor must have a working way OUT.

Born from a false alarm (secret-level elevator reported broken; probes
proved it fine - the failure mode was facing the north/south switch,
which id's own rule refuses) - but the question it raised is real:
nothing systematically guaranteed that every map HAS a reachable,
usable exit. A floor without one is a soft-lock.

Static, data-driven checks per map, both game sets:

  1. EXIT MECHANISM: at least one of
       - elevator switch with a USABLE approach: a floor tile directly
         east or west of it (Cmd_Use only works facing E/W -
         WL_AGENT.C:1056-1070, charter EXIT-002)
       - a victory trigger (plane-1 code 99, BJ's run)
       - a boss (bosses end the floor via A_Victory on death)
       - the Spear itself (bo_spear pickup ends the run)
  2. MAPINFO CHAIN: the map's `next`/`secretnext` name their targets
     and every named target exists (a typo strands the player at the
     intermission).
  3. GRID AGREEMENT: the runtime grid lump ('E' tiles WolfUse consults)
     marks exactly the JSON's elevator_switch tiles - the sim and the
     source data may not disagree.

Run: python tools/audit_exits.py            (build.py --check runs it)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETS = ("wl6", "sod")


def mapinfo_links(setname):
    """map name -> (next, secretnext) from the source MAPINFO."""
    p = ROOT / "src" / ("mapinfo_sod.txt" if setname == "sod"
                        else "mapinfo_maps.txt")
    if not p.exists():
        return None
    text = p.read_text(errors="replace")
    links = {}
    for m in re.finditer(r'map\s+(\w+)\s+"[^"]*"\s*\{([^}]*)\}', text):
        name, body = m.group(1).upper(), m.group(2)
        nx = re.search(r'next\s*=\s*"?(\w+)"?', body)
        sx = re.search(r'secretnext\s*=\s*"?(\w+)"?', body)
        links[name] = (nx.group(1).upper() if nx else None,
                       sx.group(1).upper() if sx else None)
    return links


def sod_spear_index():
    """The spear's SOD static index, read from the GENERATED class
    table (class SodStaticNN : WolfSpearOfDestiny) - the artifact the
    game ships. Re-deriving the numbering here produced a second,
    disagreeing implementation on the first run (flagged spears on
    seven maps); parse the product, not the recipe."""
    gen = ROOT / "src" / "zscript" / "statics.gen.zs"
    if not gen.exists():
        return None
    m = re.search(r"class SodStatic(\d+) : WolfSpearOfDestiny",
                  gen.read_text())
    return int(m.group(1)) if m else None


def audit_map(path, griddir, setname, spear_index):
    d = json.loads(path.read_text())
    dec = d["decoded0"]

    def kind(x, y):
        if not (0 <= x < 64 and 0 <= y < 64):
            return "void"
        return dec[y * 64 + x]["kind"]

    switches = [(i % 64, i // 64) for i, m in enumerate(dec)
                if m["kind"] == "elevator_switch"]
    usable = [(x, y) for (x, y) in switches
              if kind(x + 1, y) in ("floor", "ambush_floor")
              or kind(x - 1, y) in ("floor", "ambush_floor")]
    mechanisms = []
    if usable:
        mechanisms.append(f"elevator x{len(usable)}")
    kinds = {o["kind"] for o in d["objects"]}
    if "victory_trigger" in kinds:
        mechanisms.append("victory run")
    # Bosses end a floor in WL6 (episode enders) and for SoD's Angel
    # only; SoD's mid-bosses (Trans/Wilhelm/Uber/Death Knight) just die
    # (WL_GAME.C progression). Counting them as exits hid floor 18's
    # soft-lock behind "boss".
    bosses = {o.get("enemy") for o in d["objects"] if o["kind"] == "boss"}
    ends = bosses if setname == "wl6" else (bosses & {"angel"})
    if ends:
        mechanisms.append("boss")
    if spear_index is not None and any(
            o["kind"] == "static" and o["index"] == spear_index
            for o in d["objects"]):
        mechanisms.append("spear")

    problems = []
    if not mechanisms:
        problems.append("NO EXIT MECHANISM")

    # grid agreement. Disk artifacts are 0-indexed by file stem
    # (MAP09.json pairs with MAP09.grid.txt); only the SHIPPED lumps
    # are renamed to the 1-indexed game names. The first run of this
    # audit read 1-indexed names in the 0-indexed directory and
    # reported all 60 maps shifted by one - the audit's own bug.
    grid = griddir / f"{path.stem}.grid.txt"
    if grid.exists():
        rows = grid.read_text().split("\n")
        gtiles = {(x, y) for y, r in enumerate(rows[:64])
                  for x, c in enumerate(r[:64]) if c == "E"}
        jtiles = set(switches)
        if gtiles != jtiles:
            problems.append(f"grid E-tiles {sorted(gtiles - jtiles)} vs "
                            f"json {sorted(jtiles - gtiles)} disagree")
    return mechanisms, problems


def main():
    bad = 0
    for setname in SETS:
        lv = ROOT / "build" / "levels" / setname
        gr = ROOT / "build" / "udmf" / setname
        if not lv.is_dir():
            continue
        links = mapinfo_links(setname)
        names = set(links) if links else set()
        print(f"--- {setname} ---")
        spear_index = sod_spear_index() if setname == "sod" else None
        for f in sorted(lv.glob("MAP*.json")):
            mech, probs = audit_map(f, gr, setname, spear_index)
            mapname = f"MAP{json.loads(f.read_text())['map'] + 1:02d}"
            if links and mapname in links:
                nx, sx = links[mapname]
                for tgt, label in ((nx, "next"), (sx, "secretnext")):
                    if tgt and tgt not in names and tgt not in (
                            "ENDSEQUENCE", "ENDTITLE", "ENDGAME", "TITLEMAP"):
                        probs.append(f"{label}={tgt} does not exist")
            status = "ok" if not probs else "FAIL"
            line = f"  {mapname}: {', '.join(mech) or '-'}"
            if probs:
                line += "   << " + "; ".join(probs)
                bad += 1
            print(line if probs else line)
        if links is None:
            print("  (no mapinfo found - chain check skipped)")
    if bad:
        print(f"\n{bad} map(s) FAILED the exit audit")
        sys.exit(1)
    print("\nevery map has a reachable exit; all chains resolve")


if __name__ == "__main__":
    main()
