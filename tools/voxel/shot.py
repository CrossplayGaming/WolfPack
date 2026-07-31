#!/usr/bin/env python3
"""Drive UZDoom headlessly to photograph actors in-engine.

The voxel work needs an eye on it constantly - "does a lathe of a barrel
actually read as a barrel" is not a question any metric answers. This
runs the real engine, summons the actors in front of the player, and
saves screenshots, so every claim about how something looks is backed by
a picture taken from the shipping build rather than an assertion.

It is also the A/B rig: the same scene shot with and without
wolfvox.pk3 loaded gives sprite-vs-voxel pairs, which is the only
comparison that means anything.

  python tools/voxel/shot.py WolfStatic12 WolfStatic01
  python tools/voxel/shot.py --no-voxels WolfStatic12    # sprite control
"""
import argparse
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ENGINE = ROOT / "engine" / "uzdoom.exe"
IWAD = ROOT / "dist" / "wolf.ipk3"
PACK = ROOT / "dist" / "wolfvox.pk3"


def run(actors, out_dir, voxels=True, map_name="MAP01", tag="",
        distance=96, timeout=90):
    out_dir = Path(out_dir)
    if out_dir.exists():
        shutil.rmtree(out_dir, ignore_errors=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Three engine facts this rig is built around, each learned the hard
    # way rather than assumed:
    #
    #  1. `wait` defers the REMAINDER OF THE COMMAND BUFFER, so the whole
    #     sequence must be ONE semicolon-joined line. Written as separate
    #     lines in an exec'd cfg the waits do nothing, every command runs
    #     on the same tic, and `quit` fires before the map has loaded.
    #  2. The `map` console command is refused from this game's titlemap
    #     (GS_TITLELEVEL). `-warp N` starts on the map directly and skips
    #     the front end entirely.
    #  3. `screenshot <name>` writes relative to the WORKING DIRECTORY and
    #     ignores screenshot_dir, so the engine is run with cwd=out_dir.
    # ONE actor per engine run. `summon` spawns relative to the player
    # and nothing clears the last one, so summoning several in a row
    # photographs a pile: the third shot still has the barrel from the
    # second standing in it. A baseline frame with nothing summoned is
    # taken first so the subject can be isolated by differencing.
    seq = ["screenshot_type png", "wait 70", "god", "notarget",
           "screenshot __baseline", "wait 10"]
    for a in actors:
        seq += [f"summon {a} {distance}", "wait 15",
                f"screenshot {tag}{a}", "wait 10"]
    seq += ["wait 10", "quit"]

    cfg = out_dir / "probe.cfg"
    cfg.write_text("; ".join(seq) + "\n")

    warp = "1" if map_name.upper().startswith("MAP") else map_name
    cmd = [str(ENGINE), "-iwad", str(IWAD), "-nosound", "-nomusic",
           "-warp", str(int(map_name[3:]) if map_name[3:].isdigit()
                        else warp),
           "+exec", str(cfg)]
    if voxels:
        if not PACK.exists():
            sys.exit(f"{PACK} missing - run tools/voxel/build_pack.py first")
        cmd[3:3] = ["-file", str(PACK)]

    t0 = time.time()
    try:
        subprocess.run(cmd, timeout=timeout, capture_output=True,
                       cwd=str(out_dir))
    except subprocess.TimeoutExpired:
        print(f"  engine did not exit within {timeout}s (killed)")
    shots = sorted(p for p in out_dir.glob("*.png"))
    print(f"  {len(shots)} screenshots in {time.time() - t0:.0f}s -> {out_dir}")
    return shots


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("actors", nargs="+")
    ap.add_argument("--out", default="build/voxshots")
    ap.add_argument("--no-voxels", action="store_true",
                    help="sprite control run - do not load the pack")
    ap.add_argument("--map", default="MAP01")
    ap.add_argument("--distance", type=int, default=96)
    a = ap.parse_args()
    run(a.actors, ROOT / a.out, voxels=not a.no_voxels,
        map_name=a.map, distance=a.distance)


if __name__ == "__main__":
    main()
