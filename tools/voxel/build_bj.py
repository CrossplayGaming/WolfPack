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
# WEAPONS: each is (model, calibrated grip). The grip is per weapon and
# per rig, never per clip - solve_grip.py once, reuse forever. The body
# clips that HOLD a given weapon reference it by key.
WEAPONS = {
    # machine gun: slid forward along the barrel so the HAND sits on the
    # grip - at the solver's default the receiver rode up his forearm
    # (owner report). gripfrac 0.06 instead of 0.30.
    "mg":     (Path(r"C:\Users\cross\Desktop\Machine Gun Model.glb"),
               "0.0960,0.3139,-0.0638,-17,-169,73,0.3993"),
    # pistol: same solve, roll 180 chosen from the A/B (slide on top).
    "pistol": (Path(r"C:\Users\cross\Desktop\Pistol.glb"),
               "-0.0074,0.1059,-0.0074,172,-4,-86,0.1471"),
}
HEIGHT = 96

# Gun sprite names are DERIVED: weapon prefix + the body set's kind
# letter (WGN+S, WPS+S...). Every weapon in a clip's list gets its own
# gun set posed by that clip, so whichever weapon is equipped, the
# follower has models for every state - a pistol at his side while he
# idles, not an MG.
GUNPREFIX = {"mg": "WGN", "pistol": "WPS"}

# clip -> (glb, times, kept poses IN ORDER, body sprite, per_pose,
#          weapons whose gun sets this clip poses)
# The keep list's ORDER is honoured: pistol_fwd is the backward clip
# with the poses reversed - played A..G it reads as walking forward
# (owner's trick; per-pose mode cancels the travel, so only the leg
# cadence carries direction).
CLIPS = {
    "idle":  ("BJ Idle.glb",
              "0.000,0.253,0.496,0.787,1.085,1.438,1.704,1.900",
              [0, 1, 2, 3, 4, 5, 6], "BJ1S", False, ["mg", "pistol"]),
    "run":   ("BJ Running.glb",
              "0.000,0.103,0.203,0.271,0.377,0.481,0.602",
              [0, 1, 2, 3, 4, 6], "BJ1W", False, ["mg", "pistol"]),
    "shoot": ("BJ Shooting.glb",
              "0.000,0.142,0.295,0.456,0.592",
              [0, 2, 4], "BJ1A", True, ["mg"]),
    "pain":  ("BJ Pain.glb",
              "0.000,0.546,1.162,1.835,2.478,3.033",
              [2, 5], "BJ1P", False, ["mg", "pistol"]),
    "death": ("BJ Death.glb",
              "0.000,0.354,0.882,1.392,1.929,2.523,3.000",
              [0, 1, 2, 3, 4, 5, 6], "BJ1D", False, ["mg", "pistol"]),
    "pistol_back": ("BJ Pistol Backward.glb",
                    "0.000,0.156,0.347,0.519,0.686,0.863,1.001",
                    [0, 1, 2, 3, 4, 5, 6], "BJ1K", True, ["pistol"]),
    "pistol_fwd": ("BJ Pistol Backward.glb",
                   "0.077,0.198,0.366,0.537,0.710,0.900,1.067",
                   [6, 5, 4, 3, 2, 1, 0], "BJ1G", True, ["pistol"]),
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


def bake(glb, out, times, gun_only, weapon):
    gun, grip = WEAPONS[weapon]
    cmd = [BLENDER, "--background", "--python",
           ROOT / "tools/voxel/glb_to_obj.py", "--",
           SRC / glb, out, "--times", times, "--drop-unskinned"]
    if gun_only:
        cmd += ["--attach", gun, "--grip", grip, "--attach-only"]
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


def emit(voxdir, keep, sprite, kvx, spr):
    """Select poses IN THE GIVEN ORDER and convert to KVX.

    Copies rename to pose00.., because vox_to_kvx letters frames in
    sorted-name order - without the rename a reversed keep list would
    silently bake un-reversed. Per-pose pivot keys are remapped to the
    new names for the same reason."""
    sel = voxdir.parent / (voxdir.name + "_sel")
    if sel.exists():
        shutil.rmtree(sel)
    sel.mkdir(parents=True)
    allvox = sorted(voxdir.glob("*.vox"))
    anchors = {}
    src_anchors = {}
    if (voxdir / "frames.json").exists():
        src_anchors = json.loads((voxdir / "frames.json").read_text())
    for j, i in enumerate(keep):
        shutil.copy(allvox[i], sel / ("pose%02d.vox" % j))
        if allvox[i].stem in src_anchors:
            anchors["pose%02d" % j] = src_anchors[allvox[i].stem]
    if anchors:
        (sel / "frames.json").write_text(json.dumps(anchors, indent=1))
    if (voxdir / "frame.json").exists():
        shutil.copy(voxdir / "frame.json", sel / "frame.json")
    out = run([sys.executable, ROOT / "tools/voxel/vox_to_kvx.py",
               sel, kvx, "--name", sprite, "--sprite-dir", spr])
    # Placeholder sprites exist so the frame is valid for the voxel to
    # replace - but where the BASE GAME already ships real art for a
    # frame, a rotation-0 placeholder would sit beside 8-rotation lumps
    # of the same frame. Those get pruned (it was a hand step before,
    # which is how it got skipped on the last full rebuild).
    BASEFRAMES = {"S": "A", "W": "ABCD", "P": "AB",
                  "A": "ABC", "D": "ABCD", "F": "A"}
    if sprite.startswith("BJ"):
        for ch in BASEFRAMES.get(sprite[3], ""):
            ph = spr / ("%s%s0.png" % (sprite, ch))
            if ph.exists():
                ph.unlink()
    print("  %s: %d models" % (sprite, out.count("[verified]")))


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
        glb, times, keep, bspr, per_pose, weps = CLIPS[name]
        base = ROOT / "build/bjvox" / name
        bodyobj, bodyvox = base / "body_obj", base / "body_vox"
        print(f"\n=== {name}: {glb}")

        bake(glb, bodyobj, times, False, weps[0])
        voxelize(bodyobj, bodyvox, per_pose)
        ground_fix(bodyvox)
        if per_pose:
            run([sys.executable, ROOT / "tools/voxel/anchor_poses.py", bodyvox])

        jobs = [(bodyvox, bspr)]
        for w in weps:
            gunobj = base / ("gun_obj_" + w)
            gunvox = base / ("gun_vox_" + w)
            bake(glb, gunobj, times, True, w)
            voxelize(gunobj, gunvox, per_pose)
            run([sys.executable, ROOT / "tools/voxel/align_anchors.py",
                 bodyvox, gunvox])
            jobs.append((gunvox, GUNPREFIX[w] + bspr[3]))

        for voxdir, sprite in jobs:
            emit(voxdir, keep, sprite, kvx, spr)
        # uniform recolors of the BODY set (guns are never recolored).
        # Done here so a re-run cannot leave stale recolors behind - the
        # hand-run recolor pass predating this was exactly that trap.
        for v in (2, 3, 4):
            rc = bodyvox.parent / ("body_vox_v%d" % v)
            run([sys.executable, ROOT / "tools/voxel/recolor_vox.py",
                 bodyvox, rc, "--variant", str(v)])
            emit(rc, keep, "BJ%d%s" % (v, bspr[3]), kvx, spr)
        print("  recolors: BJ2/3/4" + bspr[3])


if __name__ == "__main__":
    main()
