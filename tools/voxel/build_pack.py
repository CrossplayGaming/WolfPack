#!/usr/bin/env python3
"""Assemble the WolfPack voxel pack (wolfvox.pk3) from the game sprites.

The pack is a SEPARATE download, not part of the compiler output. It is
loaded alongside wolf.ipk3 and switched on from the modernization menu,
so voxels stay an opt-in departure from the one-for-one recreation
rather than quietly redefining it.

Archetype assignment is decided by the DATA, not by a hand-kept list.
Every static prop is put through the lathe and then judged:

  shape_asymmetry  fraction of mirrored pixel pairs that disagree
  clipped_frac     fraction of the sprite's paint the lathe threw away

A sprite that is genuinely a solid of revolution scores near zero on
both. Anything above the thresholds is REJECTED and listed in the
report for a later archetype (hull, inflate, slab) - never quietly
shipped as a bad lathe. Hand-kept lists go stale; this re-decides on
every run against the user's own extracted art.

  python tools/voxel/build_pack.py            # build + report
  python tools/voxel/build_pack.py --report   # judge only, write nothing
"""
import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lathe                                               # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent

# A lathe is credible when the silhouette mirrors and almost no paint
# was discarded FROM THE OBJECT ITSELF. Clipping at the base is the
# sprite's painted floor shadow being correctly dropped, so it is
# reported but never held against the model - judging on total clipping
# rejects the urn, which is the archetype's best case.
MAX_ASYMMETRY = 0.05
MAX_CLIPPED = 0.12

# Items that lie flat on the floor are drawings, not objects - revolving
# them produces a disc. They belong to the SLAB archetype.
FLOOR_CLASSES = {"bo_clip", "bo_clip2", "bo_25clip", "bo_key1", "bo_key2",
                 "bo_cross", "bo_chalice", "bo_bible", "bo_crown",
                 "bo_food", "bo_firstaid", "bo_fullheal", "bo_gibs",
                 "bo_alpo", "bo_spear"}


def statics(setname):
    rows = json.loads((ROOT / "docs/data/statinfo.json").read_text())["rows"]
    out = []
    for r in rows:
        cond = r.get("cond") or ""
        if setname == "wl6" and "SPEAR" in cond and "ifndef" not in cond:
            continue
        out.append(r)
    return out


def sprite_path(setname, index):
    d = ROOT / "build" / ("assets_sod" if setname == "sod" else "assets")
    return d / "sprites" / f"S{index:03d}A0.png"


def judge(setname):
    """Lathe every static and decide which ones earned it."""
    pal = json.loads((ROOT / "build/vswap/palette.json").read_text())
    accepted, rejected = [], []
    for row in statics(setname):
        idx = row["index"]
        p = sprite_path(setname, idx)
        name = f"S{idx:03d}A"
        label = re.sub(r'\s+"?$', "", row.get("comment", "")).strip()
        if not p.exists():
            rejected.append((name, label, "no sprite extracted", None))
            continue
        if row.get("class") in FLOOR_CLASSES:
            rejected.append((name, label, "floor item - slab archetype",
                             None))
            continue
        try:
            rows_, w, h = lathe.load_indexed(p)
            paint = sum(1 for r_ in rows_ for c in r_ if c is not None)
            k, rep = lathe.build(p, pal)
        except SystemExit as e:
            rejected.append((name, label, str(e), None))
            continue
        rep["clipped_frac"] = round(rep["clipped_px"] / max(paint, 1), 4)
        rep["body_frac"] = round(
            rep["clipped_body"] / max(rep["body_paint"], 1), 4)
        # Geometry alone cannot identify a model - the barrel and the
        # well share a silhouette exactly. Fingerprint the colours too.
        rep["colours"] = len({c for r_ in rows_ for c in r_
                              if c is not None})
        if (rep["shape_asymmetry"] > MAX_ASYMMETRY
                or rep["body_frac"] > MAX_CLIPPED):
            why = (f"asym {rep['shape_asymmetry']:.3f} / "
                   f"body-clip {rep['body_frac']:.0%}")
            rejected.append((name, label, why, rep))
        else:
            accepted.append((name, label, k, rep))
    return accepted, rejected


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--set", default="wl6", choices=("wl6", "sod"))
    ap.add_argument("--out", default="dist/wolfvox.pk3")
    ap.add_argument("--report", action="store_true",
                    help="judge only; do not write the pack")
    a = ap.parse_args()

    accepted, rejected = judge(a.set)

    print(f"LATHE accepted {len(accepted)} / "
          f"{len(accepted) + len(rejected)} statics\n")
    for name, label, _k, rep in accepted:
        d = "x".join(str(v) for v in rep["dims"])
        print(f"  {name}  {label:<18.18} {d:>12}  "
              f"asym {rep['shape_asymmetry']:.3f}  "
              f"clip body {rep['body_frac']:>4.0%} base "
              f"{rep['clipped_base']:>3}  "
              f"{rep['voxels']:>5} vox  {rep['colours']:>2} cols")
    print(f"\nnot lathed ({len(rejected)}) - other archetypes:")
    for name, label, why, _ in rejected:
        print(f"  {name}  {label:<18.18} {why}")

    if a.report:
        return

    out = ROOT / a.out
    out.parent.mkdir(parents=True, exist_ok=True)
    voxeldef = ["// GENERATED by tools/voxel/build_pack.py",
                "// Sprite frame = voxel lump. Pivot and scale ride in the",
                "// KVX itself, so no per-model options are needed.", ""]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name, label, k, _rep in accepted:
            z.writestr(f"voxels/{name}.kvx", k.to_bytes())
            voxeldef.append(f'{name.lower()} = "{name.lower()}" {{}}'
                            f'   // {label}')
        z.writestr("VOXELDEF", "\n".join(voxeldef) + "\n")
    kb = out.stat().st_size / 1024
    print(f"\nwrote {out} - {len(accepted)} models, {kb:.0f} KB")


if __name__ == "__main__":
    main()
