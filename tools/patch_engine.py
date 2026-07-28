#!/usr/bin/env python3
"""Replace the engine launch art in uzdoom.pk3: the startup banner
(widgets/banner.png) and the boot logo (graphics/bootlogo.png - the
lump the startup window looks up as BOOTLOGO; the UZDoom shield by
default).

The startup window draws this art BEFORE any wad is mounted, so an
IPK3 cannot reliably shadow it - the engine's own archive must carry
it. engine/ is a local, gitignored copy, and the art is generated
from the user's game data, so nothing copyrighted is committed.
Idempotent: skips when the pk3 already holds the current bytes.
"""
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PK3 = ROOT / "engine" / "uzdoom.pk3"
REPLACE = {
    "widgets/banner.png":
        ROOT / "build" / "assets" / "widgets" / "banner.png",
    "graphics/bootlogo.png":
        ROOT / "build" / "assets" / "graphics" / "BOOTLOGO.png",
}


def main():
    if not PK3.exists():
        return
    want = {k: v.read_bytes() for k, v in REPLACE.items() if v.exists()}
    if not want:
        return
    with zipfile.ZipFile(PK3) as z:
        names = z.namelist()
        stale = {k for k, v in want.items()
                 if k not in names or z.read(k) != v}
    if not stale:
        return                              # already ours
    tmp = PK3.with_suffix(".pk3.tmp")
    with zipfile.ZipFile(PK3) as zin, \
         zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename in want:
                continue
            zout.writestr(item, zin.read(item.filename))
        for k, v in want.items():
            zout.writestr(k, v)
    shutil.move(tmp, PK3)
    print("patched engine launch art: " + ", ".join(sorted(stale)))


if __name__ == "__main__":
    main()
