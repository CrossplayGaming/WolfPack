#!/usr/bin/env python3
"""Assemble build/assets/ (gitignored) for the IPK3 from extracted data.

- PLAYPAL: 768-byte Wolf palette (GAMEPAL.OBJ, 6->8 bit)
- textures/WALLnnn.png: wall textures (from extract_vswap)
- flats/FLOOR19.png + CEILxx.png: solid-color flats per charter DATA-002
- maps/mapNN.wad: UDMF TEXTMAP wrapped in a 3-lump PWAD (from convert_udmf)

v1 scope: WL6 set, all 60 maps as MAP01..MAP60 (episode*10+map+1).
"""
import json
import shutil
import struct
from pathlib import Path

from PIL import Image

from wolf_common import ROOT, load_palette

ASSETS = ROOT / "build" / "assets"
VSWAP = ROOT / "build" / "vswap" / "wl6"
UDMF = ROOT / "build" / "udmf" / "wl6"


def png_set_grab(data: bytes, xoff: int, yoff: int) -> bytes:
    """Insert (or replace) a grAb chunk right after IHDR."""
    import zlib as _z
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    ihdr_end = 8 + 8 + struct.unpack(">I", data[8:12])[0] + 4
    payload = struct.pack(">ii", xoff, yoff)
    grab = (struct.pack(">I", 8) + b"grAb" + payload
            + struct.pack(">I", _z.crc32(b"grAb" + payload)))
    return data[:ihdr_end] + grab + data[ihdr_end:]


def wrap_wad(mapname: str, textmap: bytes) -> bytes:
    lumps = [(mapname, b""), ("TEXTMAP", textmap), ("ENDMAP", b"")]
    body = b"".join(d for _, d in lumps)
    header = struct.pack("<4sII", b"PWAD", len(lumps), 12 + len(body))
    dirents = b""
    pos = 12
    for name, d in lumps:
        dirents += struct.pack("<II8s", pos, len(d), name.encode().ljust(8, b"\x00"))
        pos += len(d)
    return header + body + dirents


def solid_flat(pal, idx):
    img = Image.new("P", (64, 64), idx)
    flat = []
    for r, g, b in pal:
        flat += [r, g, b]
    img.putpalette(flat)
    return img


def main():
    if ASSETS.exists():
        shutil.rmtree(ASSETS)
    (ASSETS / "textures").mkdir(parents=True)
    (ASSETS / "flats").mkdir()
    (ASSETS / "maps").mkdir()

    pal = load_palette()
    (ASSETS / "PLAYPAL").write_bytes(bytes(c for rgb in pal for c in rgb))

    nwalls = 0
    for png in sorted(VSWAP.glob("walls/WALL*.png")):
        shutil.copy(png, ASSETS / "textures" / png.name)
        nwalls += 1

    ceilings = json.loads((ROOT / "docs" / "data" / "ceiling_colors.json").read_text())
    solid_flat(pal, 0x19).save(ASSETS / "flats" / "FLOOR19.png")
    for c in sorted(set(ceilings["wl6"])):
        solid_flat(pal, c).save(ASSETS / "flats" / f"CEIL{c:02X}.png")

    # sprites: statics S000..S0nn (chunk 2 + row sprite, SPR_STAT_0=2 in the
    # WL6 enum) and the dead guard SDED (chunk 95). grAb origin (32,64):
    # center-bottom, so the 64x64 canvas spans floor to ceiling like the
    # original renderer. These override the committed placeholders.
    (ASSETS / "sprites").mkdir()
    statrows = json.loads((ROOT / "docs" / "data" / "statinfo.json").read_text())["rows"]
    wl6rows = [r for r in statrows
               if r["cond"] in (None, "ifndef SPEAR", "!ifdef SPEAR")]
    copies = [(2 + r["sprite"], f"S{pos:03d}A0") for pos, r in enumerate(wl6rows)]
    copies.append((95, "SDEDA0"))
    # enemy sprites (gen_enemies.py copy list)
    sc = ROOT / "docs" / "data" / "sprite_copies.json"
    if sc.exists():
        copies += [(c, n) for c, n in json.loads(sc.read_text())["copies"]]
    nspr = 0
    for chunk, name in copies:
        src = VSWAP / "sprites" / f"SPR{chunk:03d}.png"
        if src.exists():
            (ASSETS / "sprites" / f"{name}.png").write_bytes(
                png_set_grab(src.read_bytes(), 32, 64))
            nspr += 1

    # digitized sounds referenced by src/SNDINFO (wolfdigimap, WL_MAIN.C:849+)
    (ASSETS / "sounds").mkdir()
    for digi, name in ((3, "dooropen"), (2, "doorclose"), (15, "pushwall"),
                       (0, "halt"), (12, "death1"), (13, "death2"),
                       (21, "nazifire")):
        src = VSWAP / "sounds" / f"DIGI{digi:03d}.wav"
        if src.exists():
            shutil.copy(src, ASSETS / "sounds" / f"{name}.wav")

    nmaps = 0
    (ASSETS / "wolfdata").mkdir()
    for tm in sorted(UDMF.glob("MAP*.textmap")):
        n = int(tm.stem[3:])
        mapname = f"MAP{n + 1:02d}"
        (ASSETS / "maps" / f"map{n + 1:02d}.wad").write_bytes(
            wrap_wad(mapname, tm.read_bytes()))
        grid = UDMF / f"{tm.stem}.grid.txt"
        if grid.exists():
            shutil.copy(grid, ASSETS / "wolfdata" / f"{mapname}.txt")
        nmaps += 1

    print(f"assets: {nwalls} wall textures, "
          f"{len(set(ceilings['wl6'])) + 1} flats, {nmaps} maps, PLAYPAL")


if __name__ == "__main__":
    main()
