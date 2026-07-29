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


def build(spear: bool = False) -> Path:
    assets = (ROOT / "build" / "assets_sod") if spear else ASSETS
    pk3 = (DIST / "spear.ipk3") if spear else PK3
    # Always refresh build/assets from the converter outputs first — packing
    # stale maps cost a whole playtest round once. Cheap (<1s).
    if (ROOT / "build" / "udmf").is_dir():
        cmd = [sys.executable, "tools/make_assets.py"]
        if spear:
            cmd.append("sod")
        rc = subprocess.run(cmd, cwd=str(ROOT)).returncode
        if rc:
            sys.exit("make_assets failed")
        # scrub stale wolf_dbg_ values from the playtest config: any
        # launcher that bypasses play.bat's +set forces would load them
        for iniName in ("playtest.ini", "join.ini", "check.ini"):
            ini = ROOT / "dist" / iniName
            if not ini.exists():
                continue
            text = ini.read_text(errors="replace")
            # WolfPack rename: migrate config sections once
            if "[WolfDoom." in text and "[WolfPack." not in text:
                text = text.replace("[WolfDoom.", "[WolfPack.")
            kept = [l for l in text.splitlines()
                    if not l.startswith("wolf_dbg_")]
            ini.write_text(chr(10).join(kept) + chr(10))
        # launch banner lives in the ENGINE pk3 (drawn before wads mount)
        subprocess.run([sys.executable, "tools/patch_engine.py"],
                       check=False)
        # exe icon branding (in-place resource patch, idempotent)
        subprocess.run([sys.executable, "tools/patch_engine_icon.py"],
                       check=False)
    DIST.mkdir(exist_ok=True)
    if pk3.exists():
        # a freshly-written pk3 can be briefly locked by AV scanning
        # (user repro: build-failed dialog seconds after SETUP finished,
        # fine on retry) - wait it out before declaring it in use
        import time
        for _attempt in range(5):
            try:
                pk3.unlink()
                break
            except PermissionError:
                time.sleep(2)
    if pk3.exists():
        try:
            pk3.unlink()
        except PermissionError:
            sys.exit("wolf.ipk3 is in use — close the running game first, "
                     "then run play.bat again")
    asset_files = ({f.relative_to(assets).as_posix(): f
                    for f in assets.rglob("*") if f.is_file()}
                   if assets.is_dir() else {})
    # BUILDID: content hash over everything packed, so two builds show
    # the same id exactly when their pk3 content matches - netgames need
    # identical builds, and the lobby overlay displays this for an
    # eyeball check across machines (mismatched-build sessions desync)
    import hashlib
    h = hashlib.sha1()
    for f in sorted(SRC.rglob("*")):
        rel = f.relative_to(SRC).as_posix()
        if f.is_file() and rel not in asset_files:
            h.update(rel.encode()); h.update(f.read_bytes())
    for rel, f in sorted(asset_files.items()):
        h.update(rel.encode()); h.update(f.read_bytes())
    buildid = h.hexdigest()[:8]
    with zipfile.ZipFile(pk3, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(SRC.rglob("*")):
            rel = f.relative_to(SRC).as_posix()
            if not f.is_file() or rel in asset_files:
                continue
            if rel.endswith(".spear"):
                continue            # Spear overlay, handled below
            if spear and rel in ("MAPINFO", "IWADINFO"):
                continue            # replaced by the .spear overlay
            z.write(f, rel)
        if spear:
            for rel in ("MAPINFO", "IWADINFO"):
                z.write(SRC / (rel + ".spear"), rel)
        for rel, f in sorted(asset_files.items()):
            z.write(f, rel)
        z.writestr("BUILDID", buildid)
        z.writestr("GAMESET", "sod" if spear else "wl6")
    print(f"build id: {buildid}")
    print(f"built {pk3.relative_to(ROOT)} ({pk3.stat().st_size} bytes, "
          f"{len(asset_files)} extracted assets)")
    return pk3


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
    proc = subprocess.Popen([str(UZDOOM), "-iwad", str(PK3),
                             "-config", str(ROOT / "dist" / "check.ini"),
                             "+logfile",
                             str(LOG), "-nosound", "-noautoload",
                             "+set", "wolf_dbg_check", "1",
                             "+set", "wolf_dbg_doortest", "1",
                             "+set", "wolf_dbg_weapon", "1",
                             "+set", "wolf_dbg_forcefire", "1",
                             "+set", "wolf_dbg_sight", "1",
                             "+map", "MAP01"], cwd=str(ROOT))
    loaded = False
    for _ in range(75):
        time.sleep(1)
        text = LOG.read_text(errors="replace") if LOG.exists() else ""
        if ("sight: facing-player" in text
                and "weapon soak: shots=" in text):
            loaded = True
            time.sleep(1)
            break
        if "MAP01" in text:
            loaded = True          # keep waiting for the door cycle
    proc.kill()
    proc.wait()
    if not LOG.exists():
        sys.exit("self-check: no log written")
    errors, warns = [], []
    if not loaded:
        errors.append("map MAP01 never loaded (no map header in log)")

    # door-timing assertions (charter DOOR-001/002; +-1 tic transition slack)
    text = LOG.read_text(errors="replace")
    marks = dict(re.findall(r"DOORTEST (\w+) (\d+)", text))
    if "start" in marks:
        exp = (("open", "start", 32), ("closing", "open", 150),
               ("closed", "closing", 32))
        for a, b, want in exp:
            if a not in marks or b not in marks:
                errors.append(f"DOORTEST incomplete: no '{a}' mark")
                break
            got = int(marks[a]) - int(marks[b])
            if abs(got - want) > 1:
                errors.append(f"DOORTEST {b}->{a} took {got} tics, want {want}")
        else:
            print(f"  doortest: open {int(marks['open'])-int(marks['start'])}, "
                  f"autoclose {int(marks['closing'])-int(marks['open'])}, "
                  f"close {int(marks['closed'])-int(marks['closing'])} tics — OK")
    elif loaded and "DOORTEST nodoors" not in text:
        errors.append("DOORTEST never started (handler not running?)")

    # machine-gun cadence (WEAP-003): 1 shot per 12 Wolf tics = 6 engine
    # tics -> 40 shots in the 240-tic soak. Also proves no refire recursion.
    m = re.search(r"weapon soak: shots=(\d+) tics=(\d+)", text)
    if m:
        shots, tics = int(m.group(1)), int(m.group(2))
        want = tics // 6
        if abs(shots - want) > 1:
            errors.append(f"MG cadence: {shots} shots in {tics} tics, "
                          f"want {want}")
        else:
            print(f"  weapon: {shots} MG shots / {tics} tics - OK")
    elif loaded:
        errors.append("weapon soak never reported")

    # CheckSight facing rule (WL_STATE.C:1210-1231): an enemy must not see
    # the player behind it, and must wake once turned toward them.
    away = re.search(r"sight: facing-away attack=(\d)", text)
    toward = re.search(r"sight: facing-player attack=(\d)", text)
    if away and toward:
        if away.group(1) != "0":
            errors.append("sight: enemy facing AWAY woke (facing test broken)")
        elif toward.group(1) != "1":
            errors.append("sight: enemy facing the player did not wake")
        else:
            print("  sight: blind behind, wakes when facing - OK")
    elif loaded and "sight: no usable guard" not in text:
        errors.append("sight test never reported")
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
    ap.add_argument("--nospear", action="store_true")
    args = ap.parse_args()
    build()
    # Spear of Destiny is built too when the user owns its data (the
    # converter only emits build/udmf/sod when SOD files were found)
    if (ROOT / "build" / "udmf" / "sod").is_dir() and not args.nospear:
        build(spear=True)
    if args.check:
        check()
    elif args.play:
        run_engine([], timeout=None)


if __name__ == "__main__":
    main()
