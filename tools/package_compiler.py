#!/usr/bin/env python3
"""Build dist/WolfPack-compiler.zip - the asset-free distributable kit.

The kit is the git-tracked tree (which by construction contains no
copyrighted material - the repo is the legal boundary) minus the heavy
reference/ source dumps, plus the engine/ and gamedata/ placeholder
READMEs SETUP.bat expects.

This tool exists because the first kit was zipped by hand and then sat
stale on the release through two days of fixes while every other
artifact rebuilt - the same trap every hand-made artifact falls into.
Run it (or let a release script run it) after any push that should
reach testers:

    python tools/package_compiler.py
"""
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "dist" / "WolfPack-compiler.zip"

# tracked prefixes excluded from the kit (bulk reference material the
# build re-downloads via SETUP.bat / get_wolfsrc.ps1)
EXCLUDE = ("reference/",)

PLACEHOLDERS = {
    "engine/README.md":
        "SETUP.bat downloads the UZDoom engine here automatically.\n"
        "Nothing to do by hand.\n",
    "gamedata/README.md":
        "Put your own Wolfenstein 3D / Spear of Destiny data files\n"
        "here (*.WL6 and/or *.SOD). You must own the games - the\n"
        "compiler builds YOUR copy, it does not include one.\n",
}


def main():
    files = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True,
        check=True).stdout.split("\n")
    files = [f for f in files if f and not f.startswith(EXCLUDE)]
    OUT.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            p = ROOT / f
            if not p.exists():
                sys.exit(f"tracked but missing: {f} - commit or restore "
                         f"before packaging")
            z.write(p, f)
        for name, text in PLACEHOLDERS.items():
            if name in files:           # already tracked in the repo
                continue
            z.writestr(name, text)
    n = len(files) + len(PLACEHOLDERS)
    print(f"wrote {OUT} ({OUT.stat().st_size / 1e6:.1f} MB, {n} entries) "
          f"from git HEAD + placeholders")


if __name__ == "__main__":
    main()
