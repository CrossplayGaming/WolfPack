#!/usr/bin/env python3
"""Build wolf.ipk3 from src/ + build/assets and self-check it in UZDoom.

    python build.py            # assemble dist/wolf.ipk3
    python build.py --check    # assemble, launch UZDoom headlessly on MAP01,
                               # fail on ZScript/lump/map errors in the log
    python build.py --play     # assemble, then launch normally

Same loop as the Catacomb/Hovertank projects. Assets extracted from the
user's own data (tools/extract_*.py -> tools/make_assets.py) live under
build/assets (gitignored) and are merged into the IPK3 at build time.
"""
import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "src"
ASSETS = ROOT / "build" / "assets"
DIST = ROOT / "dist"
PK3 = DIST / "wolf.ipk3"
UZDOOM = ROOT / "engine" / "uzdoom.exe"
LOG = DIST / "selfcheck.log"

ERROR_PATTERNS = [
    re.compile(r"script error", re.I),
    re.compile(r"^\s*\d+ errors?(,| while)", re.I),
    re.compile(r"execution could not continue", re.I),
    re.compile(r"fatal error", re.I),
    re.compile(r"unknown class", re.I),
    re.compile(r"died with fatal", re.I),
    re.compile(r"no player 1 start", re.I),
    re.compile(r"missing", re.I),
]
WARN_PATTERNS = [
    re.compile(r"script warning", re.I),
    re.compile(r"^warning", re.I),
    re.compile(r"unknown type", re.I),
]


def build() -> Path:
    DIST.mkdir(exist_ok=True)
    if PK3.exists():
        try:
            PK3.unlink()
        except PermissionError:
            sys.exit("wolf.ipk3 is in use — close the running game first, "
                     "then run play.bat again")
    asset_files = ({f.relative_to(ASSETS).as_posix(): f
                    for f in ASSETS.rglob("*") if f.is_file()}
                   if ASSETS.is_dir() else {})
    with zipfile.ZipFile(PK3, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(SRC.rglob("*")):
            rel = f.relative_to(SRC).as_posix()
            if f.is_file() and rel not in asset_files:
                z.write(f, rel)
        for rel, f in sorted(asset_files.items()):
            z.write(f, rel)
    print(f"built {PK3.relative_to(ROOT)} ({PK3.stat().st_size} bytes, "
          f"{len(asset_files)} extracted assets)")
    return PK3


def run_engine(extra_args, timeout=90):
    if not UZDOOM.exists():
        sys.exit(f"UZDoom not found at {UZDOOM}")
    args = [str(UZDOOM), "-iwad", str(PK3), "+logfile", str(LOG)] + extra_args
    try:
        subprocess.run(args, timeout=timeout, cwd=str(ROOT))
    except subprocess.TimeoutExpired:
        print(f"  engine hung (killed after {timeout}s)")
        return 1
    return 0


def check():
    # +quit executes during startup, before the game loop runs — so to prove
    # the map loads we launch without it, poll the log for the map header,
    # then kill the engine.
    import time
    if LOG.exists():
        LOG.unlink()
    proc = subprocess.Popen([str(UZDOOM), "-iwad", str(PK3), "+logfile",
                             str(LOG), "-nosound", "-noautoload",
                             "+map", "MAP01"], cwd=str(ROOT))
    loaded = False
    for _ in range(60):
        time.sleep(1)
        if LOG.exists() and "MAP01" in LOG.read_text(errors="replace"):
            loaded = True
            time.sleep(2)          # let post-load spawn warnings flush
            break
    proc.kill()
    proc.wait()
    if not LOG.exists():
        sys.exit("self-check: no log written")
    errors, warns = [], []
    if not loaded:
        errors.append("map MAP01 never loaded (no map header in log)")
    for line in LOG.read_text(errors="replace").splitlines():
        if any(p.search(line) for p in ERROR_PATTERNS):
            errors.append(line)
        elif any(p.search(line) for p in WARN_PATTERNS):
            warns.append(line)
    for w in warns[:20]:
        print(f"  warn: {w}")
    if errors:
        print("self-check: FAILED")
        for e in errors[:30]:
            print(f"  ERROR: {e}")
        sys.exit(1)
    print(f"self-check: OK ({len(warns)} warnings)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--play", action="store_true")
    args = ap.parse_args()
    build()
    if args.check:
        check()
    elif args.play:
        run_engine([], timeout=None)


if __name__ == "__main__":
    main()
