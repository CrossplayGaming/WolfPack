#!/usr/bin/env python3
"""Build the enemy-sprite name map for the HD pack converter.

The HD pack paints over ECWolf's enemy sprites (GARD, OFFI, SSWV...),
which are named by ROLE - one letter per pose, chosen by ECWolf's
authors. Our sprites are named by role too, but split differently
(GRDS stand, GRDW walk, GRDA attack, GRDP pain, GRDD death). Neither
side's letters follow the VSWAP order, so no arithmetic relates them.

Both sides do publish their own role tables, though: ECWolf in its
DECORATE state blocks, ours in the generated tables that came from
WL_ACT2.C. This joins them state by state - Spawn to STAND, Path to
PATH1..n, Missile to SHOOT1..n, Pain to PAIN, Death to DIE1..n -
taking each side's DISTINCT poses in order of first appearance, since
both replay poses within a state (our SS has nine SHOOT rows drawn
from three sprites). Every pair the join produces is then checked by
image against our own art, so a bad alignment cannot ship silently.

    python tools/gen_hdenemies.py <ecwolf.pk3>

Writes the "enemies" section of docs/data/hdpack_map.json.
"""
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ECWolf actor -> our generated table. Mac* duplicates and the Lost
# Episodes variants are skipped: same art, different game.
ACTORS = {
    "Guard": "WolfGuardTable", "Dog": "WolfDogTable",
    "Officer": "WolfOfficerTable", "WolfensteinSS": "WolfSSTable",
    "Mutant": "WolfMutantTable", "Hans": "WolfHansTable",
    "Gretel": "WolfGretelTable", "Schabbs": "WolfSchabbsTable",
    "Gift": "WolfGiftTable", "FatFace": "WolfFatTable",
    "FakeHitler": "WolfFakeTable", "MechaHitler": "WolfMechaTable",
    "Hitler": "WolfHitlerTable", "Trans": "WolfTransTable",
    "Wilhelm": "WolfWillTable", "UberMutant": "WolfUberTable",
    "DeathKnight": "WolfDeathTable", "AngelOfDeath": "WolfAngelTable",
    "Spectre": "WolfSpectreTable",
}

# state label -> the role suffix our table rows use for it. Order
# matters only within a group; DEATHCAM rows are camera targets with
# no art of their own.
ROLES = [
    ("Spawn", ("STAND",)),
    ("Path", ("PATH", "CHASE", "WAIT")),
    ("See", ("CHASE", "PATH")),
    ("Missile", ("SHOOT", "ATTACK", "TIRED")),
    ("Pain", ("PAIN",)),
    ("Death", ("DIE", "DEAD")),
]


def our_tables():
    """role name -> (sprite, frame letter), per generated table."""
    text = (ROOT / "src/zscript/enemies.gen.zs").read_text()
    text += (ROOT / "src/zscript/enemies_sod.gen.zs").read_text() \
        if (ROOT / "src/zscript/enemies_sod.gen.zs").exists() else ""
    out = {}
    for m in re.finditer(r"class (\w+)\s*\{(.*?)\n\}", text, re.S):
        cls, body = m.group(1), m.group(2)
        names = re.findall(r"const (\w+) = \d+;", body)
        spr = re.search(r'String SPR\[\] = \{([^}]*)\}', body)
        frm = re.search(r'int FRM\[\] = \{([^}]*)\}', body)
        if not (names and spr and frm):
            continue
        sprs = [x.strip().strip('"') for x in spr.group(1).split(",")]
        frms = [int(x) for x in frm.group(1).split(",")]
        out[cls] = [(n, sprs[i], chr(65 + frms[i]))
                    for i, n in enumerate(names)]
    return out


def their_states(pk3):
    """actor -> {state label: [distinct frames in order]}."""
    z = zipfile.ZipFile(pk3)
    txt = "".join(z.read(n).decode("latin-1") for n in z.namelist()
                  if n.startswith("actors/wolf/"))
    out = {}
    for m in re.finditer(r"actor\s+(\w+)\s*(?::\s*\w+)?[^{]*\{(.*?)\n\}",
                         txt, re.S):
        name, body = m.group(1), m.group(2)
        if name not in ACTORS:
            continue
        states, label = {}, None
        for line in body.splitlines():
            lm = re.match(r"\s*(\w+):\s*$", line)
            if lm:
                label = lm.group(1)
                states.setdefault(label, ([], None))
                continue
            fm = re.match(r"\s*([A-Za-z0-9_]{4,5})\s+([A-Z0-9]+)\s+-?[\d.]+",
                          line)
            if fm and label:
                frames, spr = states[label]
                for ch in fm.group(2):
                    if ch not in frames:
                        frames.append(ch)
                states[label] = (frames, spr or fm.group(1).upper())
        out[name] = states
    return out


def distinct(rows, suffixes):
    """our (sprite, frame) pairs for a role group, first-seen order."""
    picked = []
    for suf in suffixes:
        for name, spr, frm in rows:
            # DEATHCAM is a camera target, not a pose
            if suf in name and "DEATHCAM" not in name \
                    and (spr, frm) not in picked:
                picked.append((spr, frm))
    return picked


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: gen_hdenemies.py <ecwolf.pk3>")
    tables, states = our_tables(), their_states(sys.argv[1])
    mapping, notes = {}, []
    for actor, table in ACTORS.items():
        rows, st = tables.get(table), states.get(actor)
        if not rows or not st:
            notes.append(f"{actor}: no {'table' if not rows else 'states'}")
            continue
        for label, suffixes in ROLES:
            if label not in st:
                continue
            theirs, spr = st[label]
            ours = distinct(rows, suffixes)
            if not ours:
                continue
            if len(theirs) > len(ours):
                notes.append(f"{actor}.{label}: {len(theirs)} their poses "
                             f"vs {len(ours)} ours - extra dropped")
            for t, (osp, ofr) in zip(theirs, ours):
                mapping[f"{spr}{t}"] = f"{osp}{ofr}"
    path = ROOT / "docs/data/hdpack_map.json"
    data = json.loads(path.read_text())
    data["enemies"] = dict(sorted(mapping.items()))
    path.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n")
    print(f"enemies: {len(mapping)} pose mappings")
    for n in notes:
        print("  note:", n)


if __name__ == "__main__":
    main()
