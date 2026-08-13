#!/usr/bin/env python3
"""Per-pose pivots for a PER-POSE (travelling) voxel set.

    python tools/voxel/anchor_poses.py <vox_dir> [--band 0.45 0.55]

A registered set shares one frame, so vox_to_kvx can pivot every pose at
the rig origin out of frame.json. A per-pose set has no such frame: each
pose is boxed on its own extents, so the box moves whenever a limb or a
gun extends. Pivoting at the box centre therefore slides the BODY.
Measured on BJ's shooting clip -- a 1.32 m forward travel across five
poses -- the feet swung 12.4 voxels (~7 map units) under a box-centre
pivot. In-engine that is the character skating under himself.

The anchor here is the PELVIS: the XY centroid of the voxels in a band
around hip height, with z at the pose's own floor. It beats the two
obvious alternatives, both measured on the same set:

  box centre  feet swing 12.4 voxels   (worst: gun extension moves it)
  feet        hips lurch backwards as the trailing leg swings forward
  pelvis      hips hold still, feet stride through -- walking in place

which is exactly what a travelling clip has to become, because the
ENGINE supplies the real movement and the animation must not double it.

Writes frames.json beside the .vox files; vox_to_kvx picks it up
automatically and reports the pivot it used for each pose.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_vox import read_vox                       # noqa: E402


def pelvis_anchor(path, lo, hi):
    dims, vox, _pal = read_vox(path)
    h = dims[2]
    band = [v for v in vox if lo * h <= v[2] <= hi * h]
    if not band:
        raise SystemExit(f"{path.name}: no voxels in the hip band")
    ax = sum(v[0] for v in band) / len(band)
    ay = sum(v[1] for v in band) / len(band)
    # z: the pose's own floor. A per-pose set is already self-grounded,
    # so that is the bottom of the box.
    return [ax, ay, 0.0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vox_dir")
    ap.add_argument("--band", nargs=2, type=float, default=[0.45, 0.55],
                    help="hip band as a fraction of pose height")
    a = ap.parse_args()

    d = Path(a.vox_dir)
    out = {}
    for f in sorted(d.glob("*.vox")):
        out[f.stem] = pelvis_anchor(f, a.band[0], a.band[1])
        print(f"  {f.stem}: pelvis anchor "
              f"({out[f.stem][0]:.1f}, {out[f.stem][1]:.1f})")
    if not out:
        sys.exit(f"no .vox files in {d}")
    (d / "frames.json").write_text(json.dumps(out, indent=1))
    print(f"wrote {d / 'frames.json'} - {len(out)} poses")


if __name__ == "__main__":
    main()
