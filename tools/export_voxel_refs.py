#!/usr/bin/env python3
"""Export every enemy/boss/object sprite as browsable reference PNGs.

Feeds the voxelization workflow: the owner picks reference images from
voxelize/ and generates models (Meshy) from them, the same flow the BJ
body used. Output is one transparent PNG per frame, organized by actor,
named readably (guard_walk_A_r1.png), and upscaled 8x nearest-neighbor
(512x512) so thumbnails are legible and generators get more pixels -
no information is added or lost versus the 64x64 originals, which stay
in build/assets/sprites (and _sod).

voxelize/ is UNTRACKED (gitignore) - it is extracted game art, and the
repo ships no copyrighted assets. Rerun after any extraction change:

    python tools/export_voxel_refs.py
"""
import json
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "voxelize"
SCALE = 8

# actor prefixes -> (category, folder). Categories mirror how the owner
# will voxelize: humanoids per actor, one folder each.
ACTORS = {
    "GRD": ("enemies", "guard"),
    "OFC": ("enemies", "officer"),
    "SSG": ("enemies", "ss"),
    "MUT": ("enemies", "mutant"),
    "DOG": ("enemies", "dog"),
    "BOS": ("bosses", "hans"),
    "GRE": ("bosses", "gretel"),
    "SCH": ("bosses", "schabbs"),
    "GIF": ("bosses", "giftmacher"),
    "FTB": ("bosses", "fettgesicht"),
    "FAK": ("bosses", "fake_hitler"),
    "MEC": ("bosses", "mecha_hitler"),
    "HIT": ("bosses", "hitler"),
    # Spear
    "TRN": ("bosses", "trans_grosse"),
    "UBR": ("bosses", "ubermutant"),
    "WIL": ("bosses", "wilhelm"),
    "DKN": ("bosses", "death_knight"),
    "ANG": ("bosses", "angel_of_death"),
    "SPC": ("enemies", "spectre"),
}
GHOSTS = {"BLKY": "blinky", "PNKY": "pinky",
          "INKY": "inky", "CLYD": "clyde"}
# single-sprite effects/projectiles, exact lump prefix -> name
EFFECTS = {"MISL": "rocket", "HMIS": "rocket_homing", "FIRE": "fireball",
           "HYPO": "syringe", "XP04": "rocket_boom_a",
           "XP14": "rocket_boom_b", "SPRK": "spark", "SDED": "sded"}
STATES = {"S": "stand", "W": "walk", "A": "attack", "P": "pain",
          "D": "death", "J": "leap", "T": "tired", "F": "fire"}
# player art (already voxelized), our lobby signage, first-person
# weapon overlays - not voxelization targets
SKIP = re.compile(r"^(BJ[1-4]|BJRN|BJJP|LOBS|WPIS|WMGN|WKNF|WCHN)")


def clean(comment):
    """statinfo comment -> filename: first column, sanitized."""
    name = re.split(r"\s{2,}", (comment or "unnamed").strip())[0]
    name = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_").lower()
    return name or "unnamed"


def statics_names(conds):
    rows = json.loads((ROOT / "docs/data/statinfo.json").read_text())["rows"]
    picked = [r for r in rows if r["cond"] in conds]
    # ditto marks in the source table ("") say "same note as above" for
    # the second column only; the first column is the real name
    return [clean(r["comment"]) for r in picked]


def save(im, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    big = im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)
    big.save(dest)


def export_dir(spritedir, statprefix, statnames, root, seen):
    count = 0
    for p in sorted(spritedir.glob("*.png")):
        stem = p.stem
        if SKIP.match(stem) or stem[:4] in seen:
            continue
        im = Image.open(p).convert("RGBA")
        # statics: S###A0 / D###A0
        if re.fullmatch(statprefix + r"\d\d\d[A-Z]0", stem):
            idx = int(stem[1:4])
            name = statnames[idx] if idx < len(statnames) else "row%d" % idx
            save(im, root / "objects" / ("%s%03d_%s.png" % (statprefix, idx, name)))
            count += 1
            continue
        pre4, frame, rot = stem[:4], stem[4], stem[5]
        if pre4 in GHOSTS:
            save(im, root / "ghosts" / GHOSTS[pre4] /
                 ("%s_%s.png" % (GHOSTS[pre4], frame)))
            count += 1
            continue
        if pre4 in EFFECTS:
            save(im, root / "effects" / ("%s_%s.png" % (EFFECTS[pre4], frame)))
            count += 1
            continue
        pre3, st = stem[:3], stem[3]
        if pre3 in ACTORS and st in STATES:
            cat, actor = ACTORS[pre3]
            state = STATES[st]
            fname = "%s_%s_%s" % (actor, state, frame)
            if rot != "0":
                fname += "_r" + rot
            save(im, root / cat / actor / (fname + ".png"))
            count += 1
            continue
        save(im, root / "misc" / (stem + ".png"))
        count += 1
    return count


def main():
    wl6 = ROOT / "build/assets/sprites"
    sod = ROOT / "build/assets_sod/sprites"
    if not wl6.is_dir():
        sys.exit("no build/assets/sprites - run the build first")
    n = export_dir(wl6, "S", statics_names((None, "ifndef SPEAR", "!ifdef SPEAR")),
                   OUT, seen=set())
    wl6_prefixes = {p.stem[:4] for p in wl6.glob("*.png")}
    m = 0
    if sod.is_dir():
        m = export_dir(sod, "D",
                       statics_names((None, "ifdef SPEAR", "!ifndef SPEAR")),
                       OUT / "spear", seen=wl6_prefixes)
    (OUT / "README.md").write_text("""# Voxelization reference sprites

One transparent PNG per sprite frame, upscaled 8x nearest-neighbor
(512x512) from the 64x64 originals in build/assets/sprites - crisp
pixels, nothing invented, nothing lost. Regenerate any time with
`python tools/export_voxel_refs.py`.

DO NOT COMMIT: this folder is extracted game art and stays untracked
(.gitignore) - the repo ships no assets.

## Layout

- enemies/<name>/   guard, officer, ss, mutant, dog
- bosses/<name>/    all eight WL6 bosses
- ghosts/<name>/    the E3 secret-floor spooks
- effects/          rocket, fireball, syringe, explosions
- objects/          all level statics + pickups, S###_<name>.png in
                    statinfo order
- spear/            Spear-only actors and statics (shared art like the
                    guard is not duplicated here)

## Naming

`guard_walk_A_r1.png` = actor, state, animation frame letter,
rotation. r1 faces the camera, r3 shows the actor's left side, r5 the
back, r7 the right side. Frames without rotations (deaths, pain,
statics) have no r suffix.
""", encoding="utf-8")
    print("wrote %d wl6 + %d spear sprites under %s" % (n, m, OUT))


if __name__ == "__main__":
    main()
