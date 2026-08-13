#!/usr/bin/env python3
"""Give a companion voxel set the BODY's pivot, in the companion's own
voxel space.

    python tools/voxel/align_anchors.py <body_vox_dir> <companion_vox_dir>

The gun is a separate actor drawn at the player's position, so it lines
up with the body only if both are pivoted at the SAME WORLD POINT. The
obvious way to arrange that - voxelize both in one shared grid - fails:
the gun sticks out past the body's bounding box and the voxelizer clamps
what falls outside, so the barrel collapses onto the boundary (measured:
1214 gun voxels in one pose, 117 in another).

Grids do not have to match. Only the pivot does. So each set keeps its
own tight box, and this converts the body's pivot through world space:

    world  = body_mins + body_pivot / scale
    pivot' = (world - companion_mins) * scale

Handles both set kinds - frame.json for a registered set, frames.json
plus frames_box.json for a per-pose one.
"""
import json
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    body, comp = Path(sys.argv[1]), Path(sys.argv[2])

    bfj, cfj = body / "frame.json", comp / "frame.json"
    if bfj.exists() and cfj.exists():
        b = json.loads(bfj.read_text())
        c = json.loads(cfj.read_text())
        if "mins" not in b or "mins" not in c:
            sys.exit("both sets must have been voxelized with a build that "
                     "records mins in frame.json - re-run voxelize")
        world = [b["mins"][i] + b["origin_voxel"][i] / b["scale"]
                 for i in range(3)]
        c["origin_voxel"] = [(world[i] - c["mins"][i]) * c["scale"]
                             for i in range(3)]
        cfj.write_text(json.dumps(c, indent=1))
        print(f"registered set: pivot {['%.2f' % v for v in c['origin_voxel']]}"
              f" (world {['%.3f' % v for v in world]})")
        return

    bbox = json.loads((body / "frames_box.json").read_text())
    cbox = json.loads((comp / "frames_box.json").read_text())
    banch = json.loads((body / "frames.json").read_text())
    scale = bbox["scale"]
    out = {}
    for stem, anchor in banch.items():
        if stem not in bbox["boxes"] or stem not in cbox["boxes"]:
            print(f"  skip {stem}: no box on one side")
            continue
        bmin = bbox["boxes"][stem][0]
        cmin = cbox["boxes"][stem][0]
        world = [bmin[i] + anchor[i] / scale for i in range(3)]
        out[stem] = [(world[i] - cmin[i]) * scale for i in range(3)]
        print(f"  {stem}: pivot {['%.1f' % v for v in out[stem]]}")
    (comp / "frames.json").write_text(json.dumps(out, indent=1))
    print(f"per-pose set: wrote {len(out)} pivots to {comp / 'frames.json'}")


if __name__ == "__main__":
    main()
