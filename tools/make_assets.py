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

    # View border (DrawPlayBorder, WL_GAME.C:841). The surround is palette
    # 127 and the view sits in an inset bevel: top and left in 0, bottom
    # and right in 125, and the bottom-left corner pixel in 124. Ordering
    # in the original decides the other corners - the top Hlin is drawn
    # first and then overwritten at its right end by the 125 Vlin, so
    # top-left is 0 and top-right is 125.
    (ASSETS / "graphics").mkdir(exist_ok=True)
    solid_flat(pal, 127).save(ASSETS / "flats" / "FLOOR7F.png")
    for name, idx in (("BRDR_T", 0), ("BRDR_L", 0),
                      ("BRDR_B", 125), ("BRDR_R", 125),
                      ("BRDR_TL", 0), ("BRDR_TR", 125),
                      ("BRDR_BL", 124), ("BRDR_BR", 125)):
        img = Image.new("P", (1, 1), idx)
        flatpal = []
        for r, g, b in pal:
            flatpal += [r, g, b]
        img.putpalette(flatpal)
        img.save(ASSETS / "graphics" / f"{name}.png")

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
    # intermission letter/number pics (Write(), WL_INTER.C:331-385)
    for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        hud_pics[f"L_{ch}PIC"] = f"L_{ch}"
    for i in range(10):
        hud_pics[f"L_NUM{i}PIC"] = f"L_NUM{i}"
    hud_pics["L_COLONPIC"] = "L_COLON"
    hud_pics["L_PERCENTPIC"] = "L_PCT"      # 8-char lump limit
    hud_pics["L_EXPOINTPIC"] = "L_EXCL"
    hud_pics["L_APOSTROPHEPIC"] = "L_APOS"
    hud_pics["L_GUYPIC"] = "L_GUY"
    hud_pics["L_GUY2PIC"] = "L_GUY2"
    hud_pics["L_BJWINSPIC"] = "L_BJWINS"
    # article window frame (PageLayout, WL_TEXT.C:423-427) and the one
    # graphic the end articles reference (^G16,16,5 = H_BLAZEPIC)
    hud_pics["H_TOPWINDOWPIC"] = "H_TOPWIN"
    hud_pics["H_LEFTWINDOWPIC"] = "H_LEFTW"
    hud_pics["H_RIGHTWINDOWPIC"] = "H_RIGHTW"
    hud_pics["H_BOTTOMINFOPIC"] = "H_BOTINF"
    hud_pics["H_BLAZEPIC"] = "H_BLAZE"
    # attract sequence + menu art (WL_MAIN.C DemoLoop, WL_MENU.C)
    hud_pics["HIGHSCORESPIC"] = "HISCORES"
    hud_pics["TITLEPIC"] = "TITLEPIC"
    hud_pics["CREDITSPIC"] = "CREDITS"
    hud_pics["PG13PIC"] = "PG13"
    for src, lump in (("C_OPTIONSPIC", "C_OPTS"),
                      ("C_CURSOR1PIC", "C_CURS1"),
                      ("C_CURSOR2PIC", "C_CURS2"),
                      ("C_SELECTEDPIC", "C_SEL"),
                      ("C_NOTSELECTEDPIC", "C_NOTSEL"),
                      ("C_MOUSELBACKPIC", "C_MLBACK"),
                      ("C_BABYMODEPIC", "C_BABY"),
                      ("C_EASYPIC", "C_EASY"),
                      ("C_NORMALPIC", "C_NORMAL"),
                      ("C_HARDPIC", "C_HARD"),
                      ("C_LOADGAMEPIC", "C_LOADG"),
                      ("C_SAVEGAMEPIC", "C_SAVEG"),
                      ("C_CONTROLPIC", "C_CTRL"),
                      ("C_CUSTOMIZEPIC", "C_CUSTOM"),
                      ("C_SCOREPIC", "C_SCORE"),
                      ("C_LEVELPIC", "C_LEVEL"),
                      ("C_NAMEPIC", "C_NAME"),
                      ("C_DISKLOADING1PIC", "C_DISK1"),
                      ("C_DISKLOADING2PIC", "C_DISK2")):
        hud_pics[src] = lump
    for ep in range(1, 7):
        hud_pics[f"C_EPISODE{ep}PIC"] = f"C_EPIS{ep}"

    nhud = 0
    for src_name, lump in hud_pics.items():
        p = VGA / f"{src_name}.png"
        if p.exists():
            shutil.copy(p, ASSETS / "graphics" / f"{lump}.png")
            nhud += 1

    # TITLEMAP: ZDoom uses a map of this name as the title screen, which is
    # what gives the attract sequence (PG13 -> title -> credits -> high
    # scores) a place to draw and take input. It is a sealed black box; the
    # player never sees the geometry, only the overlay.
    title_udmf = b"""namespace = "zdoom";
thing { x = 32.0; y = 32.0; angle = 90; type = 1; }
vertex { x = 0.0; y = 0.0; }
vertex { x = 64.0; y = 0.0; }
vertex { x = 64.0; y = 64.0; }
vertex { x = 0.0; y = 64.0; }
sidedef { sector = 0; texturemiddle = "WALL022"; }
sidedef { sector = 0; texturemiddle = "WALL022"; }
sidedef { sector = 0; texturemiddle = "WALL022"; }
sidedef { sector = 0; texturemiddle = "WALL022"; }
linedef { v1 = 0; v2 = 1; sidefront = 0; blocking = true; }
linedef { v1 = 1; v2 = 2; sidefront = 1; blocking = true; }
linedef { v1 = 2; v2 = 3; sidefront = 2; blocking = true; }
linedef { v1 = 3; v2 = 0; sidefront = 3; blocking = true; }
sector { heightfloor = 0; heightceiling = 64; texturefloor = "FLOOR19";
         textureceiling = "CEIL1D"; lightlevel = 0; }
"""
    (ASSETS / "maps").mkdir(exist_ok=True)
    (ASSETS / "maps" / "titlemap.wad").write_bytes(
        wrap_wad("TITLEMAP", title_udmf))

    # end-of-episode articles and the proportional font (extract_text.py)
    TXT = ROOT / "build" / "text"
    if TXT.exists():
        for ep in range(1, 7):
            src = TXT / f"endart{ep}.txt"
            if src.exists():
                shutil.copy(src, ASSETS / f"ENDART{ep}.txt")
        fsrc = TXT / "font"
        if fsrc.exists():
            fdst = ASSETS / "fonts" / "wolfprop"
            fdst.mkdir(parents=True, exist_ok=True)
            for g in fsrc.glob("*.png"):
                shutil.copy(g, fdst / g.name)

    # BJ breathing (D-005): the WL6 release stores the SAME picture for
    # both intermission frames (verified byte-identical across three
    # separate copies), so BJ cannot breathe from WL6 data alone. Spear
    # kept the proper pair, and its SECOND frame is exactly the WL6
    # picture - meaning its FIRST frame is the pose WL6 is missing. Use
    # it when the user's own Spear data is present.
    sod_guy = ROOT / "build" / "vgagraph" / "sod" / "L_GUYPIC.png"
    wl6_g1, wl6_g2 = VGA / "L_GUYPIC.png", VGA / "L_GUY2PIC.png"
    if wl6_g1.exists() and wl6_g2.exists() and sod_guy.exists():
        a = Image.open(wl6_g1).convert("RGB").tobytes()
        b = Image.open(wl6_g2).convert("RGB").tobytes()
        if a == b:
            shutil.copy(sod_guy, ASSETS / "graphics" / "L_GUY2.png")
            print("  BJ: WL6 frames identical -> second frame from Spear data")

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
    hud_item(22, "HUDKEY1")     # gold key (SPR_STAT_20)
    hud_item(23, "HUDKEY2")     # silver key (SPR_STAT_21)

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

    # music: OPL-rendered OGGs (render_adlib.py --music). The engine
    # accepted raw IMF without error but produced silence, so we ship
    # pre-rendered audio.
    (ASSETS / "music").mkdir()
    nmus = 0
    for f in sorted((ROOT / "build" / "audio" / "wl6" / "music_wav").glob("*.flac")):
        shutil.copy(f, ASSETS / "music" / f.name)
        nmus += 1

    # AdLib SFX (render_adlib.py) referenced by SNDINFO
    ADLIB = ROOT / "build" / "audio" / "wl6" / "sfx"
    (ASSETS / "sounds").mkdir(exist_ok=True)
    adlib_sfx = ["MISSILEHITSND", "PLAYERDEATHSND", "PERCENT100SND", "HEALTH1SND", "HEALTH2SND", "GETAMMOSND", "BONUS1SND",
                 "BONUS2SND", "BONUS3SND", "BONUS4SND", "BONUS1UPSND",
                 "GETKEYSND", "GETMACHINESND", "GETGATLINGSND", "NOWAYSND",
                 "ATKKNIFESND", "DOGATTACKSND", "DONOTHINGSND",
                 "LEVELDONESND", "ENDBONUS1SND", "ENDBONUS2SND",
                 "PERCENT100SND", "NOBONUSSND", "HITWALLSND"]
    for n in adlib_sfx:
        src = ADLIB / f"{n}.wav"
        if src.exists():
            shutil.copy(src, ASSETS / "sounds" / f"{n.lower()}.wav")

    # digitized sounds referenced by src/SNDINFO (wolfdigimap, WL_MAIN.C:849+)
    (ASSETS / "sounds").mkdir(exist_ok=True)
    for digi, name in ((3, "dooropen"), (2, "doorclose"), (15, "pushwall"),
                       (0, "halt"), (12, "death1"), (13, "death2"),
                       (21, "nazifire"), (5, "pistol"), (4, "machinegun"),
                       (6, "gatling"), (1, "dogbark"), (16, "dogdeath"), (22, "slurpie"),
                       (13, "death3"), (34, "death4"), (35, "death5"),
                       (39, "death6"), (40, "death7"), (41, "death8"),
                       (42, "death9"), (27, "spion"), (28, "neinsovas"),
                       (7, "schutzad"), (20, "leben"), (17, "ahhhg"),
                       (11, "ssfire"), (8, "gutentag"), (9, "mutti"),
                       (10, "bossfire"), (25, "schabbsha"), (24, "meingott"),
                       (23, "tothund"), (26, "hitlerha"), (33, "scheist"),
                       (18, "die"), (19, "eva"), (37, "eine"),
                       (38, "erlauben"), (43, "kein"), (44, "mein"),
                       (36, "donner"), (31, "mechstep"), (32, "yeah")):
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
