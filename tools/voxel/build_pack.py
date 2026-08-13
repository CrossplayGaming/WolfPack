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


# ---------------------------------------------------------------------
# The player character. Unlike the statics these are not lathed from game
# sprites - they come from the owner's own animated models through
# tools/voxel (glb_to_obj -> voxelize -> vox_to_kvx), staged under
# build/bjvox/kvx. Four uniform colours are baked, because the recolor
# rides WolfPlayer.ApplySkin's SPRITE-INDEX swap: VOXELDEF binds a voxel
# to a sprite+frame token, so BJ2SA is picked by the same swap that
# already selects the blue sprite - no new engine code for the colours.
#
# Scale: measured against the art, not derived from the collision box.
# The handoff doc's 0.58 comes from 96 voxels over a 56-unit collision
# height, but nothing in this game is drawn at its collision height --
# every figure is a 64x64 sprite with about 48 painted rows, so a guard
# (GRDSA1) and BJ's own run sprite (BJRNA0) both stand 48-49 units tall
# on screen. 96 voxels at 0.58 would have made the player 16% taller
# than every guard he walks past. 48/96 = 0.50 puts him in the cast.
CHAR_DIR = ROOT / "build/bjvox/kvx"
CHAR_SPR = ROOT / "build/bjvox/kvx_spr"
CHAR_SCALE = 0.50


def add_character(z, voxeldef):
    if not CHAR_DIR.is_dir():
        print("\nno character models staged (build/bjvox/kvx) - statics only")
        return 0
    kvx = sorted(CHAR_DIR.glob("*.kvx"))
    if not kvx:
        return 0
    voxeldef.append("")
    voxeldef.append("// player character (tools/voxel pipeline)")
    for f in kvx:
        lump = f.stem.lower()
        z.writestr(f"voxels/{lump}.kvx", f.read_bytes())
        voxeldef.append(f'{lump} = "{lump}" {{ Scale = {CHAR_SCALE} }}')
    # Placeholder sprites for the frames the base game has no art for: a
    # voxel only replaces a sprite frame's RENDERING, so the frame has to
    # exist for there to be anything to replace.
    nspr = 0
    if CHAR_SPR.is_dir():
        for f in sorted(CHAR_SPR.glob("*.png")):
            z.writestr(f"sprites/{f.name}", f.read_bytes())
            nspr += 1
    # The gun ACTOR ships here too, not in the base game: its sprite
    # frames only exist in this pack, and a state naming a frame that is
    # absent is a load error for everyone who never downloads it. The
    # base game spawns it by dynamic class lookup, so a plain build
    # simply finds nothing.
    gz = ROOT / "src/pack/gunbody.zs"
    if gz.exists():
        ver = (ROOT / "src/zscript.zs").read_text(
            errors="replace").splitlines()[0]
        z.writestr("zscript.txt", ver + "\n\n" + gz.read_text())
        print("character: + gun actor (zscript.txt)")

    # Marker lump. The base game never requires this pack, so the longer
    # voxel-only cycles have to be switched on by asking whether it is
    # loaded (voxelbody.zs) rather than by referencing frames that would
    # be missing without it.
    z.writestr("WOLFVOX", "player voxel set present\n")
    print(f"\ncharacter: {len(kvx)} models, {nspr} placeholder sprites")
    return len(kvx)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--set", default="wl6", choices=("wl6", "sod"))
    ap.add_argument("--out", default="dist/wolfvox.pk3")
    # The lathed props are OFF by default: that archetype is superseded
    # by the tools/voxel model pipeline, and the owner does not want its
    # output shipped. The judging code stays - it is still the report
    # that decides which sprites a future archetype has to handle.
    ap.add_argument("--report", action="store_true",
                    help="judge only; do not write the pack")
    ap.add_argument("--statics", action="store_true",
                    help="also ship the lathed props (off by default)")
    a = ap.parse_args()

    accepted, rejected = judge(a.set) if (a.statics or a.report) else ([], [])
    if not (a.statics or a.report):
        print("statics: skipped (--statics to include the lathed props)")

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
        nchar = add_character(z, voxeldef)
        z.writestr("VOXELDEF", "\n".join(voxeldef) + "\n")
    kb = out.stat().st_size / 1024
    print(f"\nwrote {out} - {len(accepted)} statics + {nchar} character "
          f"models, {kb:.0f} KB")


if __name__ == "__main__":
    main()
