#!/usr/bin/env python3
"""Audit: does every baked weapon set actually follow the hand?

    python tools/voxel/audit_follow.py

Owner report: "the weapon doesn't always follow the hand between poses -
floating weapon sometimes." Attachment is rigid by construction, so any
float is a PIPELINE fault (pivot, box, ordering), and those are
measurable without eyes.

For each (clip, weapon, pose) this compares two independent paths to
the same physical point - the hand bone:

  body path: bone world pos -> actor space via the BODY set's pivot
  gun path:  bone world pos -> actor space via the GUN set's own box
             and its aligned pivot

If align_anchors did its job the two agree; the drift between them is
exactly how far the weapon floats from the hand in that pose, in
voxels. Anything over ~1.5 voxels is visible in game.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BJ = ROOT / "build/bjvox"

sys.path.insert(0, str(Path(__file__).parent))
import importlib.util
spec = importlib.util.spec_from_file_location("bb", Path(__file__).parent / "build_bj.py")
bb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bb)


def actor_from_registered(fj, world):
    """actor-space position of a world point for a registered set."""
    o, mins, sc = fj["origin_voxel"], fj["mins"], fj["scale"]
    return [ (world[i] - mins[i]) * sc - o[i] for i in range(3) ]


def audit_clip(name):
    glb, times, keep, bspr, per_pose, weps = bb.CLIPS[name]
    bones = json.loads((BJ / name / "bones.json").read_text())["RightHand"]
    rows = []
    bodysel = BJ / name / "body_vox_sel"
    for w in weps:
        gunsel = BJ / name / ("gun_vox_%s_sel" % w)
        if not gunsel.is_dir():
            continue
        if per_pose:
            banch = json.loads((bodysel / "frames.json").read_text())
            ganch = json.loads((gunsel / "frames.json").read_text())
            bbox = json.loads((BJ / name / "body_vox/frames_box.json").read_text())
            gbox = json.loads((BJ / name / ("gun_vox_%s/frames_box.json" % w)).read_text())
            sc = bbox["scale"]
            ballvox = sorted(bbox["boxes"])
            gallvox = sorted(gbox["boxes"])
            for j, i in enumerate(keep):
                world = bones[i]
                key = "pose%02d" % j
                if key not in banch or key not in ganch:
                    rows.append((w, j, None, "missing anchor"))
                    continue
                bmin = bbox["boxes"][ballvox[i]][0]
                gmin = gbox["boxes"][gallvox[i]][0]
                A = [(world[k] - bmin[k]) * sc - banch[key][k] for k in range(3)]
                G = [(world[k] - gmin[k]) * sc - ganch[key][k] for k in range(3)]
                d = sum((A[k] - G[k]) ** 2 for k in range(3)) ** 0.5
                rows.append((w, j, d, ""))
        else:
            bfj = json.loads((bodysel / "frame.json").read_text())
            gfj = json.loads((gunsel / "frame.json").read_text())
            for j, i in enumerate(keep):
                world = bones[i]
                A = actor_from_registered(bfj, world)
                G = actor_from_registered(gfj, world)
                d = sum((A[k] - G[k]) ** 2 for k in range(3)) ** 0.5
                rows.append((w, j, d, ""))
    return rows


def main():
    bad = 0
    for name in bb.CLIPS:
        rows = audit_clip(name)
        worst = {}
        for w, j, d, note in rows:
            if d is None:
                print("  %-12s %-8s pose %d: %s" % (name, w, j, note))
                bad += 1
                continue
            worst[w] = max(worst.get(w, 0), d)
            if d > 1.5:
                print("  FLOAT %-12s %-8s pose %d: %.2f voxels" % (name, w, j, d))
                bad += 1
        summary = "  ".join("%s %.2f" % (w, v) for w, v in worst.items())
        print("%-13s worst drift (voxels): %s" % (name, summary))
    print("\n%s" % ("AUDIT CLEAN - no float over 1.5 voxels" if bad == 0
                    else "AUDIT: %d flagged entries" % bad))


if __name__ == "__main__":
    main()
