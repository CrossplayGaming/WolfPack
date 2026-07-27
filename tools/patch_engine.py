#!/usr/bin/env python3
"""Replace the engine launch banner (widgets/banner.png) in uzdoom.pk3.

The startup window draws its banner BEFORE any wad is mounted, so an
IPK3 cannot shadow it - the engine's own archive must carry the art.
engine/ is a local, gitignored copy, and the banner is generated from
the user's game data, so nothing copyrighted is committed. Idempotent:
skips when the pk3 already holds the current banner bytes.
"""
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PK3 = ROOT / "engine" / "uzdoom.pk3"
BANNER = ROOT / "build" / "assets" / "widgets" / "banner.png"


def main():
    if not PK3.exists() or not BANNER.exists():
        return
    want = BANNER.read_bytes()
    with zipfile.ZipFile(PK3) as z:
        names = z.namelist()
        if "widgets/banner.png" in names:
            if z.read("widgets/banner.png") == want:
                return                      # already ours
    tmp = PK3.with_suffix(".pk3.tmp")
    with zipfile.ZipFile(PK3) as zin, \
         zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == "widgets/banner.png":
                continue
            zout.writestr(item, zin.read(item.filename))
        zout.writestr("widgets/banner.png", want)
    shutil.move(tmp, PK3)
    print("patched engine launch banner")


if __name__ == "__main__":
    main()
