#!/usr/bin/env python3
"""Calibration strip for a weapon grip: one pose, several candidate
grips, side by side at voxel resolution.

    python tools/voxel/calib_grip.py <character.glb> <gun.glb> \
        --time 0.0 --sweep y=-0.08:0.08:5 [--grip 0,0,0,0,0,0,1] \
        [--bone RightHand] [--out build/bjvox/calib]

The grip transform (where the gun sits relative to the hand bone) cannot
be derived: a mesh's own origin and axis convention are arbitrary. It has
to be looked at once. This makes looking cheap - it renders the same pose
with the swept value stepped across a range, through the SAME voxelizer
the game models go through, so what you judge is what the game will draw
rather than a smooth preview that flatters it.

Fields: x y z (metres, bone space), rx ry rz (degrees), s (uniform
scale). Sweep one at a time; the winner becomes the base for the next.

Blender bone space has its origin at the bone head with +Y running along
the bone, so for a hand bone: +Y is toward the fingertips, and x/z are
across the palm.
"""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
FIELDS = ["x", "y", "z", "rx", "ry", "rz", "s"]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        sys.exit(f"failed: {' '.join(str(c) for c in cmd)}")
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("character")
    ap.add_argument("gun")
    ap.add_argument("--time", type=float, default=0.0,
                    help="which moment of the clip to pose, in seconds")
    ap.add_argument("--sweep", required=True,
                    help="field=lo:hi:steps, e.g. y=-0.08:0.08:5")
    ap.add_argument("--grip", default="0,0,0,0,0,0,1",
                    help="base grip x,y,z,rx,ry,rz,s")
    ap.add_argument("--bone", default="RightHand")
    ap.add_argument("--out", default="build/bjvox/calib")
    ap.add_argument("--height", type=int, default=96)
    ap.add_argument("--match", default="build/bjvox/idle_true/frame.json",
                    help="reference frame.json so the calibration renders "
                         "at the same scale as the shipped models")
    a = ap.parse_args()

    field, spec = a.sweep.split("=", 1)
    if field not in FIELDS:
        sys.exit(f"--sweep field must be one of {FIELDS}")
    lo, hi, steps = spec.split(":")
    lo, hi, steps = float(lo), float(hi), int(steps)
    base = [float(v) for v in a.grip.split(",")]
    if len(base) != 7:
        sys.exit("--grip needs 7 numbers: x,y,z,rx,ry,rz,s")
    idx = FIELDS.index(field)

    out = ROOT / a.out
    merged = out / "obj"
    if out.exists():
        shutil.rmtree(out)
    merged.mkdir(parents=True)

    values = [lo + (hi - lo) * i / max(1, steps - 1) for i in range(steps)]
    print(f"sweeping {field} over {values}")

    for i, v in enumerate(values):
        g = list(base)
        g[idx] = v
        stage = out / f"stage{i:02d}"
        run([str(BLENDER), "--background", "--python",
             str(ROOT / "tools/voxel/glb_to_obj.py"), "--",
             a.character, str(stage),
             "--times", str(a.time),
             "--attach", a.gun, "--bone", a.bone,
             "--grip", ",".join(str(x) for x in g)])
        # one pose per stage; rename it into the merged set so the
        # voxelizer sees the candidates as a pose sequence
        objs = sorted(stage.glob("*_p00.obj"))
        if not objs:
            sys.exit(f"candidate {i}: blender exported nothing")
        obj, mtl = objs[0], objs[0].with_suffix(".mtl")
        name = f"grip_{field}_{i:02d}"
        text = obj.read_text(errors="replace")
        if mtl.exists():
            shutil.copy(mtl, merged / f"{name}.mtl")
            text = re.sub(r"^mtllib .*$", f"mtllib {name}.mtl", text,
                          count=1, flags=re.M)
        (merged / f"{name}.obj").write_text(text)
        for tex in stage.glob("*.png"):
            shutil.copy(tex, merged / tex.name)
        print(f"  {field}={v:+.4f} -> {name}.obj")

    vox = out / "vox"
    cmd = [sys.executable, str(ROOT / "tools/voxel/voxelize.py"),
           str(merged), str(vox), "--height", str(a.height)]
    ref = ROOT / a.match
    if ref.exists():
        cmd += ["--match", str(ref)]
    run(cmd)
    sheet = out / f"calib_{field}.png"
    run([sys.executable, str(ROOT / "tools/voxel/cycle_sheet.py"),
         str(vox), str(sheet)])
    print(f"\nstrip: {sheet}")
    print(f"candidates, left to right: {[round(v, 4) for v in values]}")


if __name__ == "__main__":
    main()
