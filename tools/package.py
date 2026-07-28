#!/usr/bin/env python3
"""Assemble the personal, ready-to-play WolfPack packages.

Layout mirrors the repo so the launchers work unmodified; the compiler
is simply absent (play.bat/multiplayer.bat skip build steps when
build.py is missing). Produces, under dist/package/:
  WolfPack/                 portable folder (play anywhere)
  WolfPack-portable.zip     the same folder zipped
  WolfPack-Setup.exe        7-Zip self-extractor of the folder

These packages CONTAIN the built game data - they are for the owner
of the game data only, never for distribution. The distributable is
the compiler repo, which ships no assets.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist" / "package"
PKG = OUT / "WolfPack"
SEVENZIP = Path(r"C:\Program Files\7-Zip\7z.exe")

README = """WOLFPACK - Wolfenstein 3D, together.
A faithful multiplayer remake running on the UZDoom engine.

PLAY:         double-click WolfPack.vbs   (or play.bat for a console)
MULTIPLAYER:  in-game menu > Multiplayer  (host gets an invite code,
              joiners copy it to the clipboard and pick Join)
              or run multiplayer.bat for the same plus a local
              two-window test mode.

This package contains game data built from a legally owned copy of
Wolfenstein 3D. Do not redistribute it. The asset-free compiler that
built it: https://github.com/CrossplayGaming/WolfPack
"""


def main():
    ipk3 = ROOT / "dist" / "wolf.ipk3"
    if not ipk3.exists():
        sys.exit("no dist/wolf.ipk3 - run build.py first")
    if OUT.exists():
        shutil.rmtree(OUT)
    PKG.mkdir(parents=True)

    # engine (patched pk3 + branded exe), minus the pristine backup
    shutil.copytree(ROOT / "engine", PKG / "engine",
                    ignore=shutil.ignore_patterns("*.orig"))
    (PKG / "dist").mkdir()
    shutil.copy(ipk3, PKG / "dist" / "wolf.ipk3")
    (PKG / "tools").mkdir()
    for t in ("mp_dispatch.ps1", "mp_launch.ps1", "mod_args.ps1"):
        shutil.copy(ROOT / "tools" / t, PKG / "tools" / t)
    for f in ("play.bat", "multiplayer.bat", "WolfPack.vbs"):
        shutil.copy(ROOT / f, PKG / f)
    (PKG / "README.txt").write_text(README)

    shutil.make_archive(str(OUT / "WolfPack-portable"), "zip",
                        OUT, "WolfPack")

    if SEVENZIP.exists():
        sfx = SEVENZIP.parent / "7z.sfx"
        archive = OUT / "WolfPack.7z"
        subprocess.run([str(SEVENZIP), "a", "-t7z", "-mx=5",
                        str(archive), str(PKG)], check=True,
                       stdout=subprocess.DEVNULL)
        with open(OUT / "WolfPack-Setup.exe", "wb") as out:
            out.write(sfx.read_bytes())
            out.write(archive.read_bytes())
        archive.unlink()
    else:
        print("7-Zip not found - skipped the self-extractor")

    for p in sorted(OUT.iterdir()):
        size = (sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
                if p.is_dir() else p.stat().st_size)
        print(f"  {p.name:28s} {size / 1048576:8.1f} MB")


if __name__ == "__main__":
    main()
