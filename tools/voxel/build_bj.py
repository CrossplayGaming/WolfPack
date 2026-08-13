#!/usr/bin/env python3
"""Rebuild BJ's voxel sets - body, and the gun as a separate actor.

    python tools/voxel/build_bj.py [--clips idle,run,shoot,pain,death]

One driver so the two halves cannot drift: the gun is posed by the same
clip at the same instants as the body, then pivoted at the body's own
pivot (align_anchors.py) so the two line up in-engine without the actor
doing any offset maths.

Why the gun is separate rather than baked into the body poses:
  - the uniform recolor would paint it. Measured: 338 of the gun's 1147
    voxels in a firing pose fall inside the uniform's colour band.
  - one gun serves all four uniforms instead of four baked copies, and
    a second weapon is one more small set rather than another hundred
    body models.
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BLENDER = Path(r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
SRC = Path(r"C:\Users\cross\Desktop\HD BJ")
GUN = Path(r"C:\Users\cross\Desktop\Machine Gun Model.glb")
GRIP = "0.0436,0.1427,-0.0290,-17,-169,73,0.3993"
HEIGHT = 96

# clip -> (glb, times, kept pose indices, body sprite, gun sprite, per_pose)
CLIPS = {
    "idle":  ("BJ Idle.glb",
              "0.000,0.253,0.496,0.787,1.085,1.438,1.704,1.900",
              [0, 1, 2, 3, 4, 5, 6], "BJ1S", "WGNS", False),
    "run":   ("BJ Running.glb",
              "0.000,0.103,0.203,0.271,0.377,0.481,0.602",
              [0, 1, 2, 3, 4, 6], "BJ1W", "WGNW", False),
    "shoot": ("BJ Shooting.glb",
              "0.000,0.142,0.295,0.456,0.592",
              [0, 2, 4], "BJ1A", "WGNA", True),
    "pain":  ("BJ Pain.glb",
              "0.000,0.546,1.162,1.835,2.478,3.033",
              [2, 5], "BJ1P", "WGNP", False),
    "death": ("BJ Death.glb",
              "0.000,0.354,0.882,1.392,1.929,2.523,3.000",
              [0, 1, 2, 3, 4, 5, 6], "BJ1D", "WGND", False),
}
REF = ROOT / "build/bjvox/idle_true/frame.json"       # the scale reference


def run(cmd, quiet=True):
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-2000:])
        sys.exit("failed: " + " ".join(str(c) for c in cmd))
    if not quiet:
        print(r.stdout.strip()[-800:])
    return r.stdout


def bake(glb, out, times, gun_only):
    cmd = [BLENDER, "--background", "--python",
           ROOT / "tools/voxel/glb_to_obj.py", "--",
           SRC / glb, out, "--times", times]
    if gun_only:
        cmd += ["--attach", GUN, "--grip", GRIP, "--attach-only"]
    run(cmd)


def voxelize(objdir, voxdir, per_pose, frame_ref=None):
    cmd = [sys.executable, ROOT / "tools/voxel/voxelize.py", objdir, voxdir,
           "--height", HEIGHT]
    if per_pose:
        cmd.append("--per-pose")
    cmd += ["--match", frame_ref or REF]
    run(cmd)


def ground_fix(voxdir):
    """A clip authored FLOATING puts its rig origin outside the union box
    - BJ's pain clip never lands a sole (lowest vertex +0.081 to +0.090
    in every pose, against -0.031 for the idle), which came out as
    origin_z = -4.70 and would have hopped him ~6.6 voxels the instant he
    was hit. It was corrected by hand once and then quietly lost the
    first time this driver re-voxelized, which is why it belongs here.

    A NEGATIVE origin means the geometry never reaches the floor plane;
    legitimate variation between clips (feet lifting in a run) is
    positive and is left alone."""
    fj = Path(voxdir) / "frame.json"
    if not fj.exists():
        return
    d = json.loads(fj.read_text())
    if d["origin_voxel"][2] >= 0:
        return
    ref = json.loads(REF.read_text())["origin_voxel"][2]
    print(f"  ground fix: origin_z {d['origin_voxel'][2]:.2f} -> {ref:.2f} "
          f"(clip is authored floating)")
    d["origin_voxel"][2] = ref
    fj.write_text(json.dumps(d, indent=1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips", default=",".join(CLIPS))
    ap.add_argument("--out", default="build/bjvox/kvx")
    a = ap.parse_args()

    kvx = ROOT / a.out
    kvx.mkdir(parents=True, exist_ok=True)
    spr = ROOT / "build/bjvox/kvx_spr"
    spr.mkdir(parents=True, exist_ok=True)

    for name in a.clips.split(","):
        glb, times, keep, bspr, gspr, per_pose = CLIPS[name]
        base = ROOT / "build/bjvox" / name
        bodyobj, gunobj = base / "body_obj", base / "gun_obj"
        bodyvox, gunvox = base / "body_vox", base / "gun_vox"
        print(f"\n=== {name}: {glb}")

        bake(glb, bodyobj, times, False)
        bake(glb, gunobj, times, True)
        voxelize(bodyobj, bodyvox, per_pose)
        ground_fix(bodyvox)
        voxelize(gunobj, gunvox, per_pose)
        if per_pose:
            run([sys.executable, ROOT / "tools/voxel/anchor_poses.py", bodyvox])
        run([sys.executable, ROOT / "tools/voxel/align_anchors.py",
             bodyvox, gunvox])

        # keep only the chosen poses, in order, for each half
        for voxdir, sprite in ((bodyvox, bspr), (gunvox, gspr)):
            sel = voxdir.parent / (voxdir.name + "_sel")
            if sel.exists():
                shutil.rmtree(sel)
            sel.mkdir(parents=True)
            allvox = sorted(voxdir.glob("*.vox"))
            for i in keep:
                shutil.copy(allvox[i], sel / allvox[i].name)
            for extra in ("frame.json", "frames.json"):
                if (voxdir / extra).exists():
                    shutil.copy(voxdir / extra, sel / extra)
            out = run([sys.executable, ROOT / "tools/voxel/vox_to_kvx.py",
                       sel, kvx, "--name", sprite, "--sprite-dir", spr])
            n = out.count("[verified]")
            print(f"  {sprite}: {n} models")


if __name__ == "__main__":
    main()
