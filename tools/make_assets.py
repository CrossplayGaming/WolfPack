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

    # HUD graphics from VGAGRAPH (extract_vgagraph.py)
    VGA = ROOT / "build" / "vgagraph" / "wl6"
    (ASSETS / "graphics").mkdir(exist_ok=True)
    hud_pics = {"STATUSBARPIC": "STATBAR", "N_BLANKPIC": "N_BLANK",
                "KNIFEPIC": "KNIFEP", "GUNPIC": "GUNP",
                "MACHINEGUNPIC": "MGUNP", "GATLINGGUNPIC": "GATLINGP",
                "NOKEYPIC": "NOKEY", "GOLDKEYPIC": "GOLDKEY",
                "SILVERKEYPIC": "SILVKEY", "GETPSYCHEDPIC": "PSYCHED"}
    for i in range(10):
        hud_pics[f"N_{i}PIC"] = f"N_{i}"
    for band in range(1, 8):
        for v in "ABC":
            hud_pics[f"FACE{band}{v}PIC"] = f"FACE{band}{v}"
    hud_pics["FACE8APIC"] = "FACE8A"
    hud_pics["GOTGATLINGPIC"] = "FACEGATL"
    hud_pics["MUTANTBJPIC"] = "FACEMUTB"
    nhud = 0
    for src_name, lump in hud_pics.items():
        p = VGA / f"{src_name}.png"
        if p.exists():
            shutil.copy(p, ASSETS / "graphics" / f"{lump}.png")
            nhud += 1

    # widescreen status bar: extend by tiling an interior edge column so
    # the frame + top bevel continue to the screen edges (ECWolf look)
    barp = VGA / "STATUSBARPIC.png"
    if barp.exists():
        bar = Image.open(barp).convert("RGB")
        wide = Image.new("RGB", (1120, bar.height), (0, 65, 65))
        wide.paste(bar, ((1120 - bar.width) // 2, 0))
        # synthesized top bevel + bottom shade across the full width (the
        # source art is flat teal; this is the ECWolf widescreen look)
        for x in range(1120):
            wide.putpixel((x, 0), (0, 138, 138))
            wide.putpixel((x, bar.height - 1), (0, 36, 36))
        wide.save(ASSETS / "graphics" / "STATBAR.png")

    # minimal-HUD pickup sprites: crop to content, trim the ground-shadow
    # rows (bottom rows whose opaque pixels are all dark)
    def hud_item(chunk, lump):
        src = VSWAP / "sprites" / f"SPR{chunk:03d}.png"
        if not src.exists():
            return
        img = Image.open(src).convert("RGBA")
        # shadow/shine removal, pixel-wise: the ground shadows and floating
        # shine wisps are NEUTRAL mid-grey; item art pixels are colored
        # (sat > 14) or bright white (sum >= 500). Verified against the
        # 1-Up / medkit / clip art at 10x.
        pix = img.load()
        for y in range(img.height):
            for x in range(img.width):
                r, g, b, a = pix[x, y]
                if a > 0 and (max(r, g, b) - min(r, g, b)) <= 14 \
                        and r + g + b < 500:
                    pix[x, y] = (0, 0, 0, 0)
        img = img.crop(img.getbbox())
        img.save(ASSETS / "graphics" / f"{lump}.png")

    hud_item(35, "HUDLIFE")     # 1-Up (SPR_STAT_33)
    hud_item(27, "HUDMED")      # first aid kit (SPR_STAT_25)
    hud_item(28, "HUDAMMO")     # ammo clip (SPR_STAT_26)

    # minimal-HUD number font: N_ digits with the blue panel keyed out
    # (digits are white/periwinkle -> r+g high; panel/border blues and
    # black -> r+g near zero)
    for i in range(10):
        p = VGA / f"N_{i}PIC.png"
        if not p.exists():
            continue
        img = Image.open(p).convert("RGBA")
        pix = img.load()
        for y in range(img.height):
            for x in range(img.width):
                r, g, b, a = pix[x, y]
                if r + g < 60:
                    pix[x, y] = (0, 0, 0, 0)
        img.save(ASSETS / "graphics" / f"HN_{i}.png")

    # weapon psprites: VSWAP sprites 416-435 (ready + atk1-4 per weapon),
    # prescaled x3 (Wolf draws the 64x64 shape at full view height).
    # grAb offsets place the 192x192 image centered, bottom at the view
    # bottom in 320x200 psprite space.
    wnames = {416: "WKNF", 421: "WPIS", 426: "WMGN", 431: "WCHN"}
    nweap = 0
    for base, spr in wnames.items():
        for f in range(5):
            src = VSWAP / "sprites" / f"SPR{base + f:03d}.png"
            if not src.exists():
                continue
            img = Image.open(src)
            img = img.resize((192, 192), Image.NEAREST)
            outp = ASSETS / "sprites" / f"{spr}{chr(65 + f)}0.png"
            img.save(outp, transparency=255)
            data = outp.read_bytes()
            outp.write_bytes(png_set_grab(data, -64, 40))
            nweap += 1

    # digitized sounds referenced by src/SNDINFO (wolfdigimap, WL_MAIN.C:849+)
    (ASSETS / "sounds").mkdir()
    for digi, name in ((3, "dooropen"), (2, "doorclose"), (15, "pushwall"),
                       (0, "halt"), (12, "death1"), (13, "death2"),
                       (21, "nazifire"), (5, "pistol"), (4, "machinegun"),
                       (6, "gatling"), (1, "dogbark"), (16, "dogdeath"), (22, "slurpie")):
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
