#!/usr/bin/env python3
"""Build the voxel gallery: models on plinths beside their source sprites.

Metrics rank models; they cannot tell you whether a lathed barrel READS
as a barrel. This generates an exhibition map where each model stands
next to the sprite it came from, so a whole batch can be judged at a
glance, walked through, and filmed.

CURRENT EXHIBITION - the proof-of-concept trio (2026-07-30). The first
lathe generation taught that symmetry was the wrong gate: Wolf art is
drawn from ~8-11 degrees above, so top faces are ellipses, not profile.
The hall was cleared and now shows only the new-method attempts, one
per object tier:

  1. TRUE REVOLVE   S036 water well via lathe_top (top-face reprojection
                    - the water must lie IN the well, not stripe around
                    its wall)
  2. VIEW-SYMMETRIC S010 sink via the generative-recovery route; station
                    appears automatically when a mesh lands in import/
                    (until then the tier is represented by its absence)
  3. ENEMY HULL     guard standing frame carved from all 8 rotations

HOW BOTH SHOW AT ONCE
A voxel replaces a SPRITE NAME globally, so each model gets a second
identity: its sprite lump is copied under a V-name, a display actor is
generated to use it, and only the V-name is mapped in VOXELDEF. The
original actors are untouched - loading this pack does not alter play.

THE LAYOUT
Stations grid at 3-tile pitch; columns = round(sqrt(N*py/px)) makes the
hall roughly square in world units; the room is sized to fit the count
and errors loudly rather than overflowing Wolf's 64x64 tile cap.

  python tools/voxel/gallery.py            # writes dist/wolfvox_gallery.pk3
  python tools/voxel/gallery.py --plan     # print the layout only
"""
import argparse
import json
import math
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools"))

import convert_udmf                                        # noqa: E402
import hull                                                # noqa: E402
import lathe_top                                           # noqa: E402
from make_assets import wrap_wad                           # noqa: E402

PITCH_X = 3
PITCH_Y = 3
MARGIN = 1
APRON = 3
WALL_CODE = 1
ED_BASE = convert_udmf.ED_STATIC_BASE      # 21100; things emit base+index

SPRITES = ROOT / "build/assets/sprites"


# ---------------------------------------------------------------------------
# Station definitions. Each returns dict(label, vname, kvx, sprite_files,
# spr_actor, vox_actor) or None if its inputs are not available yet.
# ---------------------------------------------------------------------------

def station_well(pal):
    k, rep = lathe_top.build(SPRITES / "S036A0.png", pal)
    print(f"  well: {rep}")
    return {
        "label": "Water well - true revolve, top face reprojected",
        "vname": "V036",
        "kvx": k,
        # voxel display sprite = copy of the original frame
        "sprites": {"V036A0.png": SPRITES / "S036A0.png"},
        # sprite side: the game's own static actor, already defined
        "spr_ednum": ED_BASE + 36,
        "spr_class": None,
        "vox_class": ("WolfVoxShow36", "V036 A"),
    }


def station_sink(pal):
    """The generative-recovery tier. Activates when a mesh arrives."""
    for ext in ("glb", "obj"):
        for p in sorted((ROOT / "import").glob(f"sink*.{ext}")):
            print(f"  sink: found {p.name} - carve/stamp not wired yet, "
                  f"station reserved")
            return None
    print("  sink: no mesh in import/ yet - station skipped")
    return None


def station_guard(pal):
    """Meshy-reconstructed guard, both colour treatments. The hull-only
    model was judged in the gallery and retired: silhouettes hold but
    surface colour smears - 8 views cannot recover an organic surface.
    These stations exhibit the generative route instead; the KVX files
    are converted from import/ by tools/voxel/meshy.py (Blender + 28s),
    so the gallery uses the cached results rather than reconverting."""
    out = []
    variants = (("GRDM.kvx", "VGRM", "WolfVoxShowGRM",
                 "Guard - Meshy, hue-family transfer + mirror + eyes"),
                ("GRDM_raw.kvx", "VGRN", "WolfVoxShowGRN",
                 "Guard - Meshy mesh, AI texture (quantised)"))
    for i, (fname, vname, cname, label) in enumerate(variants):
        f = ROOT / "build/voxels" / fname
        if not f.exists():
            print(f"  guard: {fname} not converted yet - station skipped")
            continue
        out.append({
            "label": label,
            "vname": vname,
            "kvx_bytes": f.read_bytes(),
            "sprites": {f"{vname}A{r}.png": SPRITES / f"GRDSA{r}.png"
                        for r in range(1, 9)},
            # sprite side: an inert actor drawing the live GRDS
            # rotations (the real WolfGuard would shoot the visitors)
            "spr_ednum": ED_BASE + 496 + i,
            "spr_class": (f"WolfSprShowGRD{i}", "GRDS A"),
            "vox_class": (cname, f"{vname} A"),
        })
        print(f"  guard: {label}")
    return out


STATIONS = (station_well, station_sink, station_guard)


# ---------------------------------------------------------------------------

def plan(n):
    cols = max(1, round(math.sqrt(n * PITCH_Y / PITCH_X)))
    rows = math.ceil(n / cols)
    inner_w = (cols * PITCH_X - 1) + 2 * MARGIN
    inner_h = (rows * PITCH_Y - (PITCH_Y - 1)) + 2 * MARGIN + APRON
    if inner_w + 2 > 64 or inner_h + 2 > 64:
        raise SystemExit(f"{n} stations need {inner_w + 2}x{inner_h + 2} "
                         f"tiles; the Wolf map format caps at 64x64")
    return {"n": n, "cols": cols, "rows": rows,
            "inner_w": inner_w, "inner_h": inner_h}


def station_tile(i, g):
    c, r = i % g["cols"], i // g["cols"]
    return (1 + MARGIN + c * PITCH_X, 1 + MARGIN + r * PITCH_Y)


def build_level(pairs, g):
    """Level dict for the standard converter: pairs of (spr_idx, vox_idx)
    are statinfo-style indices (ednum - ED_BASE)."""
    dec = [{"kind": "wall", "code": WALL_CODE} for _ in range(64 * 64)]
    for y in range(1, 1 + g["inner_h"]):
        for x in range(1, 1 + g["inner_w"]):
            dec[y * 64 + x] = {"kind": "floor", "area": 0,
                               "secret_exit_pad": False, "code": 143}
    objects = []
    for i, (spr_idx, vox_idx) in enumerate(pairs):
        tx, ty = station_tile(i, g)
        objects.append({"kind": "static", "index": spr_idx,
                        "x": tx, "y": ty, "code": 23})
        objects.append({"kind": "static", "index": vox_idx,
                        "x": tx + 1, "y": ty, "code": 23})
    objects.append({"kind": "player_start", "dir": "north", "code": 19,
                    "x": 1 + g["inner_w"] // 2, "y": g["inner_h"]})
    return {"set": "wl6", "map": 90, "name": "Voxel Gallery",
            "width": 64, "height": 64, "rlew_tag": 0, "plane0": [],
            "decoded0": dec, "objects": objects}


def actor_class(name, frame):
    spr, frm = frame.split()
    return "\n".join([
        f"class {name} : Actor",
        "{",
        "    Default { +NOBLOCKMAP +NOGRAVITY +SOLID "
        "Radius 24; Height 64; }",
        f"    States {{ Spawn: {spr} {frm} -1; Stop; }}",
        "}", ""])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default="dist/wolfvox_gallery.pk3")
    ap.add_argument("--plan", action="store_true")
    a = ap.parse_args()

    pal = json.loads((ROOT / "build/vswap/palette.json").read_text())
    stations = []
    for f in STATIONS:
        r = f(pal)
        if isinstance(r, list):
            stations += r
        elif r:
            stations.append(r)
    if not stations:
        sys.exit("no stations could be built")
    g = plan(len(stations))
    print(f"\n{g['n']} stations -> {g['cols']} cols x {g['rows']} rows, "
          f"hall {g['inner_w'] + 2}x{g['inner_h'] + 2} tiles")
    for i, st in enumerate(stations):
        tx, ty = station_tile(i, g)
        print(f"  {i} ({tx:2d},{ty:2d})  {st['label']}")
    if a.plan:
        return

    # Assign voxel-display ednum indices after the statinfo range.
    zs = ["// GENERATED by tools/voxel/gallery.py", 'version "4.10"', ""]
    ednums = []
    pairs = []
    next_idx = 400
    for st in stations:
        if st["spr_class"]:
            cname, frame = st["spr_class"]
            zs.append(actor_class(cname, frame))
            spr_idx = st["spr_ednum"] - ED_BASE
            ednums.append((st["spr_ednum"], cname))
        else:
            spr_idx = st["spr_ednum"] - ED_BASE
        cname, frame = st["vox_class"]
        zs.append(actor_class(cname, frame))
        vox_idx = next_idx
        next_idx += 1
        ednums.append((ED_BASE + vox_idx, cname))
        pairs.append((spr_idx, vox_idx))

    mi = ["// GENERATED by tools/voxel/gallery.py", "DoomEdNums", "{"]
    mi += [f'    {n} = "{c}"' for n, c in ednums]
    mi += ["}", "", 'map GALLERY "Voxel Gallery"', "{",
           "    levelnum = 90", '    music = "GETTHEM"',
           '    next = "GALLERY"', "    par = 0", "}", ""]

    level = build_level(pairs, g)
    ceilings = json.loads(
        (ROOT / "docs/data/ceiling_colors.json").read_text())
    textmap, _m, _grid = convert_udmf.convert(level, ceilings["wl6"][1])

    out = ROOT / a.out
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("maps/gallery.wad", wrap_wad("GALLERY",
                                                textmap.encode()))
        z.writestr("ZSCRIPT.zs", "\n".join(zs))
        z.writestr("MAPINFO", "\n".join(mi))
        vd = ["// GENERATED by tools/voxel/gallery.py"]
        for st in stations:
            data = (st["kvx_bytes"] if "kvx_bytes" in st
                    else st["kvx"].to_bytes())
            z.writestr(f"voxels/{st['vname']}A.kvx", data)
            for arc, src in st["sprites"].items():
                z.writestr(f"sprites/{arc}", src.read_bytes())
            vd.append(f'{st["vname"].lower()}a = '
                      f'"{st["vname"].lower()}a" {{}}   // {st["label"]}')
        z.writestr("VOXELDEF", "\n".join(vd) + "\n")
    print(f"\nwrote {out} ({out.stat().st_size / 1024:.0f} KB)")
    print("play: gallery.bat")


if __name__ == "__main__":
    main()
