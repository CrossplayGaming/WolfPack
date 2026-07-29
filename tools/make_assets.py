#!/usr/bin/env python3
"""Assemble build/assets/ (gitignored) for the IPK3 from extracted data.

- PLAYPAL: 768-byte Wolf palette (GAMEPAL.OBJ, 6->8 bit)
- textures/WALLnnn.png: wall textures (from extract_vswap)
- flats/FLOOR19.png + CEILxx.png: solid-color flats per charter DATA-002
- maps/mapNN.wad: UDMF TEXTMAP wrapped in a 3-lump PWAD (from convert_udmf)

Runs per GAME SET (argv, default wl6):
  wl6 -> build/assets      -> dist/wolf.ipk3   60 maps as MAP01..MAP60
  sod -> build/assets_sod  -> dist/spear.ipk3  21 maps as MAP01..MAP21
The two ipk3s are separate files, so each owns its lump namespace and
nothing needs renaming between them; only the chunk->lump mappings and
the static DoomEd range differ (gen_statics emits both sets).
"""
import json
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image

from wolf_common import ROOT, load_palette

SET = "sod" if "sod" in sys.argv[1:] else "wl6"
IS_SOD = SET == "sod"
# Spear statics are SodStatic** with D-prefixed sprite lumps (gen_statics)
SPRPFX = "D" if IS_SOD else "S"

ASSETS = ROOT / "build" / ("assets_sod" if IS_SOD else "assets")
VSWAP = ROOT / "build" / "vswap" / SET
UDMF = ROOT / "build" / "udmf" / SET


def _png_bytes(img) -> bytes:
    import io
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


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


# Our SNDINFO's logical names -> the source's sound enum names. The
# INDEX behind each differs per build (wolfdigimap has #ifndef SPEAR /
# #else branches), which is why this is resolved from the source per
# game rather than hardcoded: Spear's index 21 is the dog attack, while
# WL6's is the guard's rifle - so a fixed table gave Spear's soldiers a
# barking gun.
DIGI_NAMES = {
    "OPENDOORSND": "dooropen", "CLOSEDOORSND": "doorclose",
    "PUSHWALLSND": "pushwall", "HALTSND": "halt",
    "DEATHSCREAM1SND": "death1", "DEATHSCREAM2SND": "death2",
    "DEATHSCREAM3SND": "death3", "DEATHSCREAM4SND": "death4",
    "DEATHSCREAM5SND": "death5", "DEATHSCREAM6SND": "death6",
    "DEATHSCREAM7SND": "death7", "DEATHSCREAM8SND": "death8",
    "DEATHSCREAM9SND": "death9", "NAZIFIRESND": "nazifire",
    "ATKPISTOLSND": "pistol", "ATKMACHINEGUNSND": "machinegun",
    "ATKGATLINGSND": "gatling", "DOGBARKSND": "dogbark",
    "DOGDEATHSND": "dogdeath", "SLURPIESND": "slurpie",
    "SPIONSND": "spion", "NEINSOVASSND": "neinsovas",
    "SCHUTZADSND": "schutzad", "LEBENSND": "leben",
    "AHHHGSND": "ahhhg", "SSFIRESND": "ssfire",
    "GUTENTAGSND": "gutentag", "MUTTISND": "mutti",
    "BOSSFIRESND": "bossfire", "SCHABBSHASND": "schabbsha",
    "MEINGOTTSND": "meingott", "TOT_HUNDSND": "tothund",
    "HITLERHASND": "hitlerha", "SCHEISTSND": "scheist",
    "DIESND": "die", "EVASND": "eva", "EINESND": "eine",
    "ERLAUBENSND": "erlauben", "KEINSND": "kein", "MEINSND": "mein",
    "DONNERSND": "donner", "MECHSTEPSND": "mechstep",
    "YEAHSND": "yeah", "ROSESND": "rose",
    "TRANSSIGHTSND": "transsight", "TRANSDEATHSND": "transdeath",
    "WILHELMSIGHTSND": "willsight", "WILHELMDEATHSND": "willdeath",
    "UBERDEATHSND": "uberdeath", "KNIGHTSIGHTSND": "knightsight",
    "KNIGHTDEATHSND": "knightdeath", "ANGELSIGHTSND": "angelsight",
    "ANGELDEATHSND": "angeldeath", "GETSPEARSND": "getspear",
    "DOGATTACKSND": "dogattack",
}


def digimap_for_build():
    """[(digi index, our lump name)] from wolfdigimap for THIS build."""
    import re
    src = ROOT / "reference" / "wolfsrc" / "WOLFSRC" / "WL_MAIN.C"
    if not src.exists():
        return []
    text = src.read_text(errors="replace")
    i = text.find("wolfdigimap")
    body = text[i:text.find("};", i)]
    # walk the conditional stack, keeping only the branches this build
    # compiles (the Spear block also holds its boss voices)
    out, stack = [], []
    for line in body.splitlines():
        t = line.strip()
        if t.startswith("#ifndef SPEARDEMO"):
            stack.append(True)          # we are not the Spear demo
            continue
        if t.startswith("#ifndef SPEAR"):
            stack.append(not IS_SOD)
            continue
        if t.startswith("#ifdef SPEAR"):
            stack.append(IS_SOD)
            continue
        if t.startswith("#if"):
            # any other conditional (#ifndef UPLOAD): we build the full
            # game, and it MUST still push a frame or its #endif pops
            # the Spear condition and both branches leak through
            stack.append(t.startswith("#ifndef"))
            continue
        if t.startswith("#else"):
            if stack:
                stack[-1] = not stack[-1]
            continue
        if t.startswith("#endif"):
            if stack:
                stack.pop()
            continue
        if not all(stack):
            continue
        m = re.match(r"(\w+SND)\s*,\s*(\d+)", t)
        if m and m.group(1) in DIGI_NAMES:
            out.append((int(m.group(2)), DIGI_NAMES[m.group(1)]))
    return out


_ENUM_CACHE = None


def _enum_early():
    """This build's sprite enum (cached); Spear shifts many indices."""
    global _ENUM_CACHE
    if _ENUM_CACHE is None:
        import sys as _s
        _s.path.insert(0, str(ROOT / "tools"))
        from gen_enemies import sprite_enum
        _ENUM_CACHE = sprite_enum(spear=IS_SOD)
    return _ENUM_CACHE


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
    for c in sorted(set(ceilings[SET])):
        solid_flat(pal, c).save(ASSETS / "flats" / f"CEIL{c:02X}.png")

    # sprites: statics S000..S0nn (chunk 2 + row sprite, SPR_STAT_0=2 in the
    # WL6 enum) and the dead guard SDED (chunk 95). grAb origin (32,64):
    # center-bottom, so the 64x64 canvas spans floor to ceiling like the
    # original renderer. These override the committed placeholders.
    (ASSETS / "sprites").mkdir()
    statrows = json.loads((ROOT / "docs" / "data" / "statinfo.json").read_text())["rows"]
    conds = ((None, "ifdef SPEAR", "!ifndef SPEAR") if IS_SOD
             else (None, "ifndef SPEAR", "!ifdef SPEAR"))
    wl6rows = [r for r in statrows if r["cond"] in conds]
    copies = [(2 + r["sprite"], f"{SPRPFX}{pos:03d}A0")
              for pos, r in enumerate(wl6rows)]
    # the dead-guard decoration: chunk 95 in WL6 but 99 in Spear, so
    # resolve it by name like everything else (hardcoding it drew some
    # other sprite as Spear's corpses)
    if "SPR_GRD_DEAD" in _enum_early():
        copies.append((_enum_early()["SPR_GRD_DEAD"], "SDEDA0"))
    # enemy sprites (gen_enemies.py copy list)
    sc = ROOT / "docs" / "data" / f"sprite_copies_{SET}.json"
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
    VGA = ROOT / "build" / "vgagraph" / SET
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

    # Spear splits its title screen into two VGAGRAPH chunks (320x80 over
    # 320x120); stack them so the shared attract code finds one TITLEPIC
    if IS_SOD:
        t1, t2 = VGA / "TITLE1PIC.png", VGA / "TITLE2PIC.png"
        if t1.exists() and t2.exists():
            a, b = Image.open(t1).convert("RGB"), Image.open(t2).convert("RGB")
            title = Image.new("RGB", (max(a.width, b.width),
                                      a.height + b.height))
            title.paste(a, (0, 0))
            title.paste(b, (0, a.height))
            (ASSETS / "graphics").mkdir(exist_ok=True)
            title.save(ASSETS / "graphics" / "TITLEPIC.png")
        # Spear's own menu/ending art
        for src, lump in (("C_WONSPEARPIC", "C_WONSPR"),
                          ("ENDPICPIC", "ENDPIC"),
                          ("C_HOWTOUGHPIC", "C_HOWTGH")):
            f = VGA / f"{src}.png"
            if f.exists():
                shutil.copy(f, ASSETS / "graphics" / f"{lump}.png")
        for n in (3, 4, 5, 6, 7, 8, 9, 11, 12):
            f = VGA / f"ENDSCREEN{n}PIC.png"
            if f.exists():
                shutil.copy(f, ASSETS / "graphics" / f"ENDSCR{n:02d}.png")

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
sidedef { sector = 0; texturemiddle = "WALL000"; }
sidedef { sector = 0; texturemiddle = "WALL000"; }
sidedef { sector = 0; texturemiddle = "WALL000"; }
sidedef { sector = 0; texturemiddle = "WALL000"; }
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

    # AdLib menu blips (render_adlib.py output): cursor, toggle, select,
    # escape - these replace the engine's Doom menu sounds via SNDINFO
    (ASSETS / "sounds").mkdir(exist_ok=True)
    SFX = ROOT / "build" / "audio" / SET / "sfx"
    for wav in ("MOVEGUN1SND", "MOVEGUN2SND", "SHOOTSND", "ESCPRESSEDSND"):
        src = SFX / f"{wav}.wav"
        if src.exists():
            shutil.copy(src, ASSETS / "sounds" / f"{wav.lower()}.wav")

    # menu mouse cursor: a keyed classic arrow (user: the gun pic sits in
    # an opaque box; a pointer should point). White fill, black outline,
    # hotspot at the top-left tip where the engine anchors CursorPic.
    ARROW = ["X          ", "XX         ", "XWX        ", "XWWX       ",
             "XWWWX      ", "XWWWWX     ", "XWWWWWX    ", "XWWWWWWX   ",
             "XWWWWWWWX  ", "XWWWWWWWWX ", "XWWWWWXXXXX", "XWWXWWX    ",
             "XWX XWWX   ", "XX  XWWX   ", "     XWWX  ", "      XX   "]
    cur = Image.new("RGBA", (11, 16), (0, 0, 0, 0))
    cpx = cur.load()
    for cy, row in enumerate(ARROW):
        for cx, ch in enumerate(row):
            if ch == "X":
                cpx[cx, cy] = (0, 0, 0, 255)
            elif ch == "W":
                cpx[cx, cy] = (255, 247, 0, 255)        # READHCOLOR yellow
    cur.save(ASSETS / "graphics" / "M_CURSOR.png")

    # launch-window banner: shadow the engine's widgets/banner.png with
    # the game's own title art (built from the user's data, not shipped)
    tp = VGA / "TITLEPIC.png"
    if tp.exists():
        (ASSETS / "widgets").mkdir(exist_ok=True)
        # the engine banner is a 1366x197 strip: centre the title art on
        # it at 4:3 rather than stretching it to the strip
        img = Image.open(tp).convert("RGB").resize((263, 197),
                                                   Image.NEAREST)
        strip = Image.new("RGB", (1366, 197), (0, 0, 0))
        strip.paste(img, ((1366 - 263) // 2, 0))
        strip.save(ASSETS / "widgets" / "banner.png")

    # the menu gun cursor pics carry a solid background box: key it out
    # by the corner color so the gun floats over any page
    for lump in ("C_CURS1", "C_CURS2"):
        cp = ASSETS / "graphics" / f"{lump}.png"
        if cp.exists():
            img = Image.open(cp).convert("RGBA")
            cpx = img.load()
            key = cpx[0, 0]
            for yy in range(img.height):
                for xx in range(img.width):
                    if cpx[xx, yy] == key:
                        cpx[xx, yy] = (0, 0, 0, 0)
            img.save(cp)

    # Lobby signage: the multiplayer lobby's selectable alcoves get
    # floating labels. Rendering them to SPRITES (rather than doing
    # world-to-screen math in ZScript, which this engine exposes no
    # helper for) means the engine handles perspective, scaling and
    # occlusion for free. One sprite name, 11 labels x 2 states:
    # frames A-K unselected (grey), L-V selected (gold).
    fontbig_dir = ROOT / "build" / "text" / ("sod_fontbig" if IS_SOD
                                             else "fontbig")
    if fontbig_dir.exists():
        LABELS = ["EPISODE 1", "EPISODE 2", "EPISODE 3", "EPISODE 4",
                  "EPISODE 5", "EPISODE 6", "CAN I PLAY DADDY",
                  "DONT HURT ME", "BRING EM ON", "DEATH INCARNATE",
                  "START GAME"]
        GREY, GOLD = (142, 142, 142), (255, 247, 0)

        def render_label(text, rgb):
            glyphs = []
            for ch in text:
                g = fontbig_dir / f"{ord(ch):04X}.png"
                if g.exists():
                    glyphs.append(Image.open(g).convert("RGBA"))
                else:
                    glyphs.append(None)          # space
            w = sum((g.width if g else 5) + 1 for g in glyphs) + 4
            h = max((g.height for g in glyphs if g), default=13) + 4
            img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            x = 2
            for g in glyphs:
                if g is None:
                    x += 6
                    continue
                tint = Image.new("RGBA", g.size, rgb + (255,))
                tint.putalpha(g.split()[3])
                img.paste(tint, (x, 2), tint)
                x += g.width + 1
            # 1px black outline so the text reads against any wall
            a = img.split()[3]
            out = Image.new("RGBA", img.size, (0, 0, 0, 0))
            px, ap = out.load(), a.load()
            for yy in range(img.height):
                for xx in range(img.width):
                    if ap[xx, yy]:
                        continue
                    near = False
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = xx + dx, yy + dy
                        if (0 <= nx < img.width and 0 <= ny < img.height
                                and ap[nx, ny]):
                            near = True
                            break
                    if near:
                        px[xx, yy] = (0, 0, 0, 255)
            out.alpha_composite(img)
            return out

        nlab = 0
        for i, text in enumerate(LABELS):
            for state, rgb in ((0, GREY), (1, GOLD)):
                img = render_label(text, rgb)
                frame = chr(65 + i + state * 11)     # A-K grey, L-V gold
                # grAb: centred horizontally, baseline at the bottom, so
                # the actor's z is where the label's underside floats
                (ASSETS / "sprites" / f"LOBS{frame}0.png").write_bytes(
                    png_set_grab(_png_bytes(img), img.width // 2,
                                 img.height))
                nlab += 1
        print(f"  lobby signage: {nlab} label sprites")

    # boot logo (256x256): the engine's startup window looks up lump
    # BOOTLOGO (the UZDoom shield by default). Composed from the
    # extracted Wolf big font - generated from the user's data like
    # everything else, nothing committed. Shipped in the IPK3 (lump
    # shadowing) and stamped into the engine pk3 by patch_engine.py.
    fontbig = ROOT / "build" / "text" / ("sod_fontbig" if IS_SOD
                                        else "fontbig")
    userlogo = ROOT / "import" / "bootlogo.png"
    if userlogo.exists() and fontbig.exists():
        # user-made WolfPack lettering (transparent background): crop to
        # the art, fit onto the charcoal canvas, tagline underneath
        logo = Image.new("RGB", (256, 256), (20, 20, 20))
        art = Image.open(userlogo).convert("RGBA")
        bb = art.split()[3].getbbox()
        art = art.crop(bb)
        aspect = art.width / art.height
        if 0.9 <= aspect <= 1.1:
            # complete square badge (frame, panel, credit) - use whole
            art = art.resize((256, 256), Image.LANCZOS)
            logo.paste(art, (0, 0), art)
            logo.save(ASSETS / "graphics" / "BOOTLOGO.png")
            print("  boot logo: full-badge import art")
            return_early = True
        else:
            return_early = False
        if not return_early:
            w = 244
            h = min(150, round(art.height * w / art.width))
            art = art.resize((w, h), Image.LANCZOS)
            logo.paste(art, ((256 - w) // 2, (190 - h) // 2), art)
        grey = (142, 142, 142)
        def blit_tag(word, y, scale, color):
            imgs = []
            for ch in word:
                g = fontbig / f"{ord(ch):04X}.png"
                if g.exists():
                    imgs.append(Image.open(g).convert("RGBA"))
            tw = sum(i.width for i in imgs) + (len(imgs) - 1)
            x = (256 - tw * scale) // 2
            for i in imgs:
                big = i.resize((i.width * scale, i.height * scale),
                               Image.NEAREST)
                tint = Image.new("RGBA", big.size, color + (255,))
                tint.putalpha(big.split()[3])
                logo.paste(tint, (x, y), tint)
                x += (i.width + 1) * scale
        if not return_early:
            blit_tag("WOLFENSTEIN 3D TOGETHER", 214, 1, grey)
            logo.save(ASSETS / "graphics" / "BOOTLOGO.png")
            print("  boot logo composed from import/bootlogo.png")
    elif fontbig.exists():
        logo = Image.new("RGB", (256, 256), (20, 20, 20))
        gold = (255, 247, 0)
        grey = (142, 142, 142)
        def blit_word(word, y, scale, color):
            imgs = []
            for ch in word:
                g = fontbig / f"{ord(ch):04X}.png"
                if g.exists():
                    imgs.append(Image.open(g).convert("RGBA"))
            w = sum(i.width for i in imgs) + (len(imgs) - 1)
            x = (256 - w * scale) // 2
            for i in imgs:
                big = i.resize((i.width * scale, i.height * scale),
                               Image.NEAREST)
                tint = Image.new("RGBA", big.size, color + (255,))
                tint.putalpha(big.split()[3])
                logo.paste(tint, (x, y), tint)
                x += (i.width + 1) * scale
        blit_word("WOLF", 52, 4, gold)
        blit_word("PACK", 122, 4, gold)
        blit_word("WOLFENSTEIN 3D TOGETHER", 208, 1, grey)
        for yy in (40, 196):
            for xx in range(24, 232):
                logo.putpixel((xx, yy), (113, 0, 0))
        logo.save(ASSETS / "graphics" / "BOOTLOGO.png")
        print("  boot logo generated")

    # multiplayer player sprites (gen_playersprite.py output): packed so
    # other players render in netgames - the missing-sprite diamond over
    # an invisible obstacle in the first 2-player test was player two
    PSPR = ROOT / "build" / "playersprite"
    if PSPR.exists():
        for png in PSPR.glob("BJ*.png"):
            (ASSETS / "sprites" / png.name).write_bytes(
                png_set_grab(png.read_bytes(), 32, 64))

    # end-of-episode articles and the proportional font (extract_text.py)
    TXT = ROOT / "build" / "text"
    if TXT.exists():
        # WL6 has six episode articles; Spear has ONE ending text and no
        # Read This! page, so packing WL6's would show the wrong game's
        # story (they come from the WL6 VGAGRAPH)
        for ep in range(1, 7 if not IS_SOD else 2):
            src = TXT / (f"endart{ep}.txt" if not IS_SOD
                         else "sod_endart1.txt")
            if src.exists():
                shutil.copy(src, ASSETS / f"ENDART{ep}.txt")
        if not IS_SOD and (TXT / "helpart.txt").exists():
            shutil.copy(TXT / "helpart.txt", ASSETS / "HELPART.txt")
        # smallfont/bigfont are the engine's own UI fonts: packing the
        # Wolf glyphs under those reserved names restyles every engine-
        # drawn string (obituaries, DM scoreboard, notify lines) for
        # stylistic parity with the rest of the game
        # per game: Spear ships its own font chunks (its big font
        # differs from WL6's), extracted as sod_font / sod_fontbig
        _fp = "sod_" if IS_SOD else ""
        for srcname, fontname in ((_fp + "font", "wolfprop"),
                                  (_fp + "fontbig", "wolfbig"),
                                  (_fp + "font", "smallfont"),
                                  (_fp + "fontbig", "bigfont")):
            fsrc = TXT / srcname
            if fsrc.exists():
                fdst = ASSETS / "fonts" / fontname
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
    # Resolved from THIS build's sprite enum, not fixed chunk numbers:
    # Spear shifts the whole weapon block down by 15 (knife ready is 401
    # there, 416 in WL6), which drew the pistol as a chaingun. The source
    # indexes weaponscale[weapon] + weaponframe, i.e. frames run
    # contiguously from each weapon's READY sprite - and the machine gun
    # has only FOUR (its enum jumps ATK2 -> ATK4), so a fifth frame read
    # into the chaingun.
    _enum = _enum_early()
    wnames = {}
    # every weapon really does have five frames (READY + four attack);
    # the "machine gun has four" reading came from the dropped enum slot
    for ready, spr, nframes in (("SPR_KNIFEREADY", "WKNF", 5),
                                ("SPR_PISTOLREADY", "WPIS", 5),
                                ("SPR_MACHINEGUNREADY", "WMGN", 5),
                                ("SPR_CHAINREADY", "WCHN", 5)):
        if ready in _enum:
            wnames[_enum[ready]] = (spr, nframes)
    nweap = 0
    for base, (spr, nframes) in wnames.items():
        for f in range(nframes):
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
    for f in sorted((ROOT / "build" / "audio" / SET / "music_wav").glob("*.flac")):
        shutil.copy(f, ASSETS / "music" / f.name)
        nmus += 1

    # AdLib SFX (render_adlib.py) referenced by SNDINFO
    ADLIB = ROOT / "build" / "audio" / SET / "sfx"
    (ASSETS / "sounds").mkdir(exist_ok=True)
    adlib_sfx = ["MISSILEHITSND", "PLAYERDEATHSND", "PERCENT100SND", "HEALTH1SND", "HEALTH2SND", "GETAMMOSND", "BONUS1SND",
                 "BONUS2SND", "BONUS3SND", "BONUS4SND", "BONUS1UPSND",
                 "GETKEYSND", "GETMACHINESND", "GETGATLINGSND", "NOWAYSND",
                 "ATKKNIFESND", "DOGATTACKSND", "DONOTHINGSND",
                 "LEVELDONESND", "ENDBONUS1SND", "ENDBONUS2SND",
                 "PERCENT100SND", "NOBONUSSND", "HITWALLSND"]
    # Spear's boss voices are AdLib, not digitised - pack them by their
    # sound-enum names alongside the shared set
    adlib_sfx += ["GHOSTSIGHTSND", "GHOSTFADESND", "ANGELSIGHTSND",
                  "ANGELDEATHSND", "ANGELFIRESND", "ANGELTIREDSND",
                  "TRANSSIGHTSND", "TRANSDEATHSND", "UBERDEATHSND",
                  "KNIGHTSIGHTSND", "KNIGHTDEATHSND", "KNIGHTMISSILESND",
                  "WILHELMSIGHTSND", "WILHELMDEATHSND", "GETSPEARSND",
                  "SPIONSND"]
    for n in adlib_sfx:
        src = ADLIB / f"{n}.wav"
        if src.exists():
            shutil.copy(src, ASSETS / "sounds" / f"{n.lower()}.wav")

    # digitized sounds referenced by src/SNDINFO (wolfdigimap, WL_MAIN.C:849+)
    (ASSETS / "sounds").mkdir(exist_ok=True)
    for digi, name in digimap_for_build():
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

    # multiplayer lobby (convert_udmf LOBBY variant of Hans's level)
    lobby = UDMF / "LOBBY.textmap"
    if lobby.exists():
        (ASSETS / "maps" / "lobby.wad").write_bytes(
            wrap_wad("LOBBY", lobby.read_bytes()))
        lgrid = UDMF / "LOBBY.grid.txt"
        if lgrid.exists():
            shutil.copy(lgrid, ASSETS / "wolfdata" / "LOBBY.txt")
        nmaps += 1

    print(f"assets: {nwalls} wall textures, "
          f"{len(set(ceilings[SET])) + 1} flats, {nmaps} maps, PLAYPAL")


if __name__ == "__main__":
    main()
