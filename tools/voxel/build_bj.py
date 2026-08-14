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
# WEAPONS: model per weapon. Grips are PER (weapon, clip) now - the
# owner placed every weapon in every state himself with grip_lab.html
# (Weapon Stuff/ capture set), and one bone-relative grip per weapon
# could never be right in every pose anyway (the knife saga). The
# converted lines live in grips_owner.json; death reuses idle.
WEAPONS = {
    "mg":      Path(r"C:\Users\cross\Desktop\Machine Gun Model.glb"),
    "pistol":  Path(r"C:\Users\cross\Desktop\Pistol.glb"),
    "knife":   Path(r"C:\Users\cross\Desktop\HD BJ\Knife.glb"),
    "bazooka": Path(r"C:\Users\cross\Desktop\HD BJ\Bazooka.glb"),
}
FLASH_GLB = Path(r"C:\Users\cross\Desktop\Muzzle Flash.glb")
GRIPS = json.loads((Path(__file__).parent
                    / "grips_owner.json").read_text())
# the bone world scale every solve printed; folds grip lines to and
# from actual basis matrices when composing the flash onto the gun
BONE_K = 0.0100
HEIGHT = 96

# Gun sprite names are DERIVED: weapon prefix + the body set's kind
# letter (WGN+S, WPS+S...). Every weapon in a clip's list gets its own
# gun set posed by that clip, so whichever weapon is equipped, the
# follower has models for every state - a pistol at his side while he
# idles, not an MG.
GUNPREFIX = {"mg": "WGN", "pistol": "WPS", "knife": "WKN",
             "bazooka": "WBZ"}
# muzzle-flash sets, baked only for the fire clips
FLASHPREFIX = {"mg": "FMG", "pistol": "FPS", "bazooka": "FBZ"}
FIRECLIPS = {"pistol_fwd", "pistol_back",
             "longgun_fwd", "longgun_back"}

# clip -> (glb, times, kept poses IN ORDER, body sprite, per_pose,
#          weapons whose gun sets this clip poses)
# The keep list's ORDER is honoured: pistol_fwd is the backward clip
# with the poses reversed - played A..G it reads as walking forward
# (owner's trick; per-pose mode cancels the travel, so only the leg
# cadence carries direction).
CLIPS = {
    "idle":  ("BJ Idle.glb",
              "0.000,0.253,0.496,0.787,1.085,1.438,1.704,1.900",
              [0, 1, 2, 3, 4, 5, 6], "BJ1S", False,
              ["mg", "pistol", "knife", "bazooka"]),
    "run":   ("BJ Running.glb",
              "0.000,0.103,0.203,0.271,0.377,0.481,0.602",
              [0, 1, 2, 3, 4, 6], "BJ1W", False,
              ["mg", "pistol", "knife", "bazooka"]),
    "pain":  ("BJ Pain.glb",
              "0.000,0.546,1.162,1.835,2.478,3.033",
              [2, 5], "BJ1P", False, ["mg", "pistol", "knife", "bazooka"]),
    "death": ("BJ Death.glb",
              "0.000,0.354,0.882,1.392,1.929,2.523,3.000",
              [0, 1, 2, 3, 4, 5, 6], "BJ1D", False,
              ["mg", "pistol", "knife", "bazooka"]),
    # walking backward, NOT firing - whatever is held comes along
    "walk_back": ("BJ Backwards.glb",
                  "0.000,0.084,0.151,0.234,0.331,0.426,0.533",
                  [0, 1, 2, 3, 4, 5, 6], "BJ1B", True,
                  ["mg", "pistol", "knife", "bazooka"]),
    "pistol_back": ("BJ Pistol Backward.glb",
                    "0.000,0.156,0.347,0.519,0.686,0.863,1.001",
                    [0, 1, 2, 3, 4, 5, 6], "BJ1K", True, ["pistol"]),
    "pistol_fwd": ("BJ Pistol Backward.glb",
                   "0.077,0.198,0.366,0.537,0.710,0.900,1.067",
                   [6, 5, 4, 3, 2, 1, 0], "BJ1G", True, ["pistol"]),
    # the long-gun directional pair supersedes the old advancing-fire
    # clip (BJ1A); same reversed-order trick for the forward set
    "longgun_back": ("BJ Long Gun Backwards.glb",
                     "0.000,0.216,0.451,0.664,0.859,1.093",
                     [0, 1, 2, 3, 4, 5], "BJ1M", True, ["mg", "bazooka"]),
    "longgun_fwd": ("BJ Long Gun Backwards.glb",
                    "0.168,0.395,0.625,0.841,1.057,1.300",
                    [5, 4, 3, 2, 1, 0], "BJ1L", True, ["mg", "bazooka"]),
    # knife attack; registered set - the lunge travels WITHIN the pose,
    # like the death fall
    "stab":  ("BJ Stab.glb",
              "1.829,1.941,2.288,3.133,3.488",
              [0, 1, 2, 3, 4], "BJ1T", False, ["knife"]),
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


import math


def line_to_mat(line, k):
    g = [float(v) for v in line.split(",")]
    a, b, c = (math.radians(v) for v in g[3:6])
    cx, sx = math.cos(a), math.sin(a)
    cy, sy = math.cos(b), math.sin(b)
    cz, sz = math.cos(c), math.sin(c)
    R = [[cy*cz, sx*sy*cz - cx*sz, cx*sy*cz + sx*sz],
         [cy*sz, sx*sy*sz + cx*cz, cx*sy*sz - sx*cz],
         [-sy,   sx*cy,            cx*cy]]
    sc = g[6] / k
    M = [[R[i][j]*sc for j in range(3)] + [g[i]/k] for i in range(3)]
    return M + [[0, 0, 0, 1]]


def mat_to_line(M, k):
    import math as m
    sc = m.sqrt(sum(M[i][0]**2 for i in range(3)))
    R = [[M[i][j]/sc for j in range(3)] for i in range(3)]
    ey = m.asin(max(-1, min(1, -R[2][0])))
    ex = m.atan2(R[2][1], R[2][2])
    ez = m.atan2(R[1][0], R[0][0])
    return "%.4f,%.4f,%.4f,%.1f,%.1f,%.1f,%.4f" % (
        M[0][3]*k, M[1][3]*k, M[2][3]*k,
        m.degrees(ex), m.degrees(ey), m.degrees(ez), sc*k)


def matmul(A, B):
    return [[sum(A[i][t]*B[t][j] for t in range(4)) for j in range(4)]
            for i in range(4)]


# The owner's verdict on the first in-game flash: "way more pronounced".
# Bake the flash models 40% larger than his captures; the Lighting
# menu's Muzzle Flash slider tunes light/glow/duration live around this
# baseline. Scales about the flash's own centre, so it stays on the
# muzzle.
FLASH_SCALE = 1.4


def flash_grip(weapon, clip_key):
    """Compose the owner's flash-on-gun placement onto that clip's gun
    grip: basis_flash = basis_gun @ Y @ F_gltf @ inv(Y), with Y the
    fixed glTF-to-Blender +90-about-X. Everything stays in the legacy
    7-number format, so the bake path needs nothing new."""
    gun = GRIPS["grips"]["%s/%s" % (weapon, clip_key)]
    F = GRIPS["flash"][weapon]          # column-major, three.js
    Fm = [[F[0]*FLASH_SCALE, F[4]*FLASH_SCALE, F[8]*FLASH_SCALE,  F[12]],
          [F[1]*FLASH_SCALE, F[5]*FLASH_SCALE, F[9]*FLASH_SCALE,  F[13]],
          [F[2]*FLASH_SCALE, F[6]*FLASH_SCALE, F[10]*FLASH_SCALE, F[14]],
          [0, 0, 0, 1]]
    Y = [[1, 0, 0, 0], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]]
    Yi = [[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]]
    B = matmul(line_to_mat(gun["line"], BONE_K), matmul(Y, matmul(Fm, Yi)))
    return mat_to_line(B, BONE_K), gun["bone"]


def bake(glb, out, times, weapon=None, clip_key=None, flash=False):
    cmd = [BLENDER, "--background", "--python",
           ROOT / "tools/voxel/glb_to_obj.py", "--",
           SRC / glb, out, "--times", times, "--drop-unskinned"]
    if weapon is not None:
        if flash:
            line, bone = flash_grip(weapon, clip_key)
            mesh = FLASH_GLB
        else:
            g = GRIPS["grips"]["%s/%s" % (weapon, clip_key)]
            line, bone = g["line"], g["bone"]
            mesh = WEAPONS[weapon]
        cmd += ["--attach", mesh, "--grip", line, "--attach-only",
                "--bone", bone]
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


def build_clip(name, kvx, spr):
    glb, times, keep, bspr, per_pose, weps = CLIPS[name]
    base = ROOT / "build/bjvox" / name
    bodyobj, bodyvox = base / "body_obj", base / "body_vox"
    print(f"\n=== {name}: {glb}")

    bake(glb, bodyobj, times)
    voxelize(bodyobj, bodyvox, per_pose)
    ground_fix(bodyvox)
    if per_pose:
        run([sys.executable, ROOT / "tools/voxel/anchor_poses.py", bodyvox])

    jobs = [(bodyvox, bspr)]
    for w in weps:
        gunobj = base / ("gun_obj_" + w)
        gunvox = base / ("gun_vox_" + w)
        bake(glb, gunobj, times, w, name)
        voxelize(gunobj, gunvox, per_pose)
        run([sys.executable, ROOT / "tools/voxel/align_anchors.py",
             bodyvox, gunvox])
        jobs.append((gunvox, GUNPREFIX[w] + bspr[3]))
        if name in FIRECLIPS and w in FLASHPREFIX:
            fobj = base / ("flash_obj_" + w)
            fvox = base / ("flash_vox_" + w)
            bake(glb, fobj, times, w, name, flash=True)
            voxelize(fobj, fvox, per_pose)
            run([sys.executable, ROOT / "tools/voxel/align_anchors.py",
                 bodyvox, fvox])
            jobs.append((fvox, FLASHPREFIX[w] + bspr[3]))

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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips", default=",".join(CLIPS))
    ap.add_argument("--out", default="build/bjvox/kvx")
    ap.add_argument("--jobs", type=int, default=4,
                    help="clips baked concurrently. Clips are fully "
                         "independent (own work dirs, distinct KVX names), "
                         "and the work is process-parallel - Blender "
                         "launches and the voxelizer - so wall clock "
                         "scales close to linearly until cores run out.")
    a = ap.parse_args()

    kvx = ROOT / a.out
    kvx.mkdir(parents=True, exist_ok=True)
    spr = ROOT / "build/bjvox/kvx_spr"
    spr.mkdir(parents=True, exist_ok=True)

    names = a.clips.split(",")
    if a.jobs <= 1:
        for name in names:
            build_clip(name, kvx, spr)
        return
    import concurrent.futures as cf
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = {ex.submit(build_clip, n, kvx, spr): n for n in names}
        for f in cf.as_completed(futs):
            f.result()          # propagate the first failure loudly


if __name__ == "__main__":
    main()
