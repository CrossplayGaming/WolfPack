#!/usr/bin/env python3
"""Convert the ECWolf RMST HD pack into WolfPack addon pk3s.

Runs on the USER'S machine against THEIR downloaded copy of the pack -
WolfPack ships only this converter and the name map
(docs/data/hdpack_map.json), never the art. Credit: RMST ("ECWolf
Unofficial Remaster") by its author on ModDB; the original readme is
copied into the output pack.

    python tools/convert_hdpack.py <RMST folder or ECWolf_RMST.pk3>

Produces:
    dist/hdtex.pk3   HD walls/statics/pickups/weapons (wolf_mod_hdtex)
    dist/hdsfx.pk3   remastered sounds (wolf_mod_hdsfx), if the SFX
                     pk3 sits beside the texture pk3

Every art mapping is VERIFIED BY IMAGE before packing: the RMST lump
is downscaled and compared against our extracted original; a mapping
whose distance is far worse than its runner-up match is reported and
skipped rather than silently shipping wrong art (the off-by-one class
of bug in this project's history all died by exactly this kind of
check). ECWolf enemy sprites are not converted yet - the frame-role
join is a follow-up; the pack is useful without them.
"""
import io
import json
import re
import sys
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MAP = json.loads((ROOT / "docs/data/hdpack_map.json").read_text())

# our SNDINFO logical names <- RMST wav basenames.
#
# Derived from the pack's OWN SNDINFO (its logical-name -> wav join is
# authored data, not a guess): every line RMST leaves ENABLED is
# carried over here under our equivalent name. The pack also ships
# remastered enemy voices but has them commented out; honoring that is
# deliberate, since that is how its author shipped it.
SFX_MAP = {
    # weapons - RMST's gatling is W_VENO; GGUN is its ammo-box pickup
    "wolf/knife": "W_KNIF", "wolf/pistol": "W_LUGR",
    "wolf/machinegun": "W_MP40", "wolf/gatling": "W_VENO",
    # world
    "wolf/dooropen": "DROPN", "wolf/doorclose": "DRCLS",
    "wolf/pushwall": "PWALL", "wolf/noway": "DOORLCK9",
    "wolf/missilehit": "KABOOM",
    # player
    "wolf/playerdeath": "BJDIE", "wolf/yeah": "BJYEAH",
    "wolf/donothing": "BJGRUNT",
    # pickups: BONUS1-4 = cross, chalice, chest, crown; HEALTH1 = meal,
    # HEALTH2 = first aid (WL_DEF.H bonus order)
    "wolf/bonus1": "GOTLOOT", "wolf/bonus2": "GOTLOOT",
    "wolf/bonus3": "GOTCHEST", "wolf/bonus4": "GOTCROWN",
    "wolf/bonus1up": "EXTRA", "wolf/getammo": "AMMOPU",
    "wolf/getgatling": "GOTGGUN", "wolf/getmachine": "GOTWEAP",
    "wolf/health1": "EATMEAL", "wolf/health2": "BJAAH",
    "wolf/getkey": "KEY02",
    # menus: SFXMENU1 select, 2 move, 3 escape
    "menu/advance": "sfxmenu1", "menu/choose": "sfxmenu1",
    "menu/activate": "sfxmenu1", "menu/prompt": "sfxmenu1",
    "menu/cursor": "sfxmenu2", "menu/change": "sfxmenu2",
    "menu/invalid": "sfxmenu2", "menu/backup": "sfxmenu3",
    "menu/clear": "sfxmenu3", "menu/dismiss": "sfxmenu3",
    # intermission tally
    "wolf/endbonus1": "BONUS", "wolf/endbonus2": "cashreg",
    "wolf/percent100": "cashreg", "wolf/nobonus": "nobon",
}


_thumbs = {}


def _thumb(img):
    """32x32 thumbnail with transparency flattened onto one fixed
    backdrop. Going straight to RGB is wrong for our palette sprites:
    PIL fills transparent pixels with whatever color sits at that
    palette index, so a mostly-empty sprite (the knife is ~95% air)
    gets compared on its BACKGROUND rather than its art - which is how
    the knife once lost its argmin to a Pac-Man ghost easter egg."""
    img = img.convert("RGBA")
    # crop to the art's own bounding box: the two packs frame their
    # sprites on differently sized canvases (our 192px view weapons vs
    # their 128px), so comparing raw canvases compares placement, not
    # art - which flagged the pistol and machine gun as mismatches
    box = img.getbbox()
    if box:
        img = img.crop(box)
    bg = Image.new("RGBA", img.size, (0, 255, 0, 255))
    return Image.alpha_composite(bg, img).convert("RGB")         .resize((32, 32)).load()


def _thumb_set(kind):
    """Downscaled thumbnails of ALL our lumps of a kind, cached."""
    if kind in _thumbs:
        return _thumbs[kind]
    ours_dir = (ROOT / "build/vswap/wl6/walls" if kind == "wall"
                else ROOT / "build/assets/sprites")
    t = {}
    for f in ours_dir.glob("*.png"):
        t[f.stem] = _thumb(Image.open(f))
    _thumbs[kind] = t
    return t


def _dist(pa, pb):
    return sum(abs(pa[x, y][c] - pb[x, y][c])
               for x in range(0, 32, 2) for y in range(0, 32, 2)
               for c in range(3))


def verify(hd_png, our_name, kind, family=""):
    """RELATIVE check: a remaster legitimately differs from the
    original in absolute pixels, so absolute thresholds condemned half
    the (correct) map. The mapping is wrong only if some OTHER
    original matches the HD art clearly better than the mapped one -
    the argmin test that exposed nothing less than the truth for every
    off-by-one in this project's history.

    `family` names a group of lumps (a weapon's five view frames) whose
    members are interchangeable answers: the HD idle art can resemble
    our recoil frame more than our idle frame, and that says nothing
    about whether we picked the right WEAPON. Which frame gets which
    art comes from the pack's own TEXTURES join, not from this check."""
    thumbs = _thumb_set(kind)
    if our_name not in thumbs:
        return None, "our lump missing"
    hd = _thumb(Image.open(io.BytesIO(hd_png)))
    d_target = _dist(hd, thumbs[our_name])
    best_name, best_d = our_name, d_target
    for name, pt in thumbs.items():
        d = _dist(hd, pt)
        if d < best_d:
            best_name, best_d = name, d
    if family and best_name.startswith(family):
        return d_target, None
    if best_name != our_name and best_d < d_target * 0.75:
        return d_target, f"argmin is {best_name} ({best_d} vs {d_target})"
    return d_target, None


def parse_textures(text):
    """RMST TEXTURES entries: name, size, scales, offsets, patch."""
    out = {}
    for m in re.finditer(
            r'(Texture|Sprite)\s+(?:Optional\s+)?(\w+),\s*(\d+),\s*(\d+)'
            r'\s*\{([^}]*)\}', text, re.I):
        out[m.group(2).upper()] = (m.group(1), int(m.group(3)),
                                   int(m.group(4)), m.group(5))
    return out


def weapons(z, names, tex_defs, o, textures_lump):
    """First-person weapon frames.

    The pack draws its five view frames from three or four painted
    images, animating the rest with per-frame vertical offsets (the gun
    rising with recoil), and it publishes that join in its own TEXTURES
    lump - so the frame->art mapping is read, never guessed. Only the
    idle frame's art is image-verified against ours; the rest inherit
    the pack's authored join.

    Geometry is copied VERBATIM from those entries - canvas size,
    scale, offsets - and only the sprite name changes. The pack was
    authored against ECWolf, whose view-sprite placement matches this
    engine's, so its own numbers put each weapon exactly where its
    author intended; screenshot-compared against the pack running under
    ECWolf, they land the same. Deriving placement instead (fitting
    their art onto our sprite's bounding box) was tried first and
    misjudged both size and height, because their art is cropped at the
    canvas edge where ours floats inside a larger frame.
    """
    n = 0
    written = set()
    for ec, ours in sorted(MAP["weapons"].items()):
        frames = {}
        for fr in "ABCDE":
            td = tex_defs.get(f"{ec}{fr}0")
            if not td:
                continue
            _, w, h, body = td
            pm = re.search(r"Patch\s+(\w+)", body, re.I)
            if pm:
                frames[fr] = (pm.group(1), w, h, " ".join(body.split()))
        if "A" not in frames:
            print(f"  skipped weapon {ec}: no idle frame in the pack")
            continue
        # image-verify the idle art against our idle frame
        patchA = frames["A"][0]
        data = z.read(f"sprites/default/{patchA}.png")
        d, err = verify(data, f"{ours}A0", "sprite", family=ours)
        if err:
            print(f"  SUSPECT weapon {ec} -> {ours}: {err}")
            continue
        for fr, (patch, w, h, body) in sorted(frames.items()):
            path = f"sprites/default/{patch}.png"
            if path not in names:
                continue
            if patch not in written:
                o.writestr(f"patches/{patch}.png", z.read(path))
                written.add(patch)
            textures_lump.append(f"Sprite {ours}{fr}0, {w}, {h} {{{body}}}")
            n += 1
    return n


def convert(src):
    src = Path(src)
    pk3 = src if src.suffix == ".pk3" else src / "ECWolf_RMST.pk3"
    if not pk3.exists():
        sys.exit(f"{pk3} not found")
    z = zipfile.ZipFile(pk3)
    names = z.namelist()

    tex_defs = {}
    for lump in ("TEXTURES.wall", "TEXTURES.spr"):
        if lump in names:
            tex_defs.update(parse_textures(
                z.read(lump).decode("latin-1")))

    out = ROOT / "dist/hdtex.pk3"
    converted = skipped = suspect = 0
    textures_lump = ["// GENERATED by convert_hdpack.py from ECWolf "
                     "RMST - art (c) its author, converted locally"]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
        # walls
        for ec, ours in sorted(MAP["walls"].items()):
            path = f"textures/default/{ec}.png"
            if path not in names:
                skipped += 1
                continue
            data = z.read(path)
            d, err = verify(data, ours, "wall")
            if err:
                print(f"  SUSPECT wall {ec} -> {ours}: {err}")
                suspect += 1
                continue
            o.writestr(f"patches/{ours}.png", data)
            textures_lump.append(
                f"Texture {ours}, 128, 128 {{ XScale 2 YScale 2 "
                f"Patch {ours}, 0, 0 }}")
            converted += 1
        # statics/pickups: single frame A0
        sprite_map = dict(MAP["sprites"])
        for ec, ours in sorted(sprite_map.items()):
            for n in names:
                m = re.match(rf"sprites/default/{ec}(\w\d)\.png$", n)
                if not m:
                    continue
                frame = m.group(1)
                data = z.read(n)
                dst = f"{ours}{frame}"
                d, err = verify(data, dst, "sprite")
                if err:
                    print(f"  SUSPECT sprite {ec}{frame} -> {dst}: {err}")
                    suspect += 1
                    continue
                o.writestr(f"sprites/{dst}.png", data)
                # carry RMST's own offsets, scaled entry verbatim
                td = tex_defs.get(f"{ec}{frame}")
                if td:
                    _, w, h, body = td
                    body = re.sub(rf"\b{ec}{frame}\b", dst, body)
                    textures_lump.append(
                        f"Sprite {dst}, {w}, {h} {{{body}}}")
                converted += 1
        converted += weapons(z, names, tex_defs, o, textures_lump)
        o.writestr("TEXTURES.hd", "\n".join(textures_lump) + "\n")
        for r in names:
            if "readme" in r.lower():
                o.writestr("RMST_README.txt", z.read(r))

    print(f"hdtex.pk3: {converted} lumps converted, {skipped} skipped "
          f"(not in pack), {suspect} suspect mappings withheld")

    # ---- sounds ---------------------------------------------------------
    sfx = pk3.parent / "ECWolf_RMST_SFX.pk3"
    if sfx.exists():
        zs = zipfile.ZipFile(sfx)
        sn = ["// GENERATED: RMST remastered sounds under WolfPack "
              "logical names"]
        got = 0
        with zipfile.ZipFile(ROOT / "dist/hdsfx.pk3", "w",
                             zipfile.ZIP_DEFLATED) as o:
            wavs = {Path(n).stem.upper(): n for n in zs.namelist()
                    if n.lower().endswith(".wav")}
            packed = set()          # several logical names share a wav
            for logical, base in SFX_MAP.items():
                if base.upper() not in wavs:
                    print(f"  missing wav for {logical}: {base}")
                    continue
                dst = f"sounds/hd_{base.lower()}.wav"
                if dst not in packed:
                    o.writestr(dst, zs.read(wavs[base.upper()]))
                    packed.add(dst)
                sn.append(f'{logical}  "{dst}"')
                got += 1
            o.writestr("SNDINFO.hd", "\n".join(sn) + "\n")
        print(f"hdsfx.pk3: {got}/{len(SFX_MAP)} sounds mapped")


if __name__ == "__main__":
    convert(sys.argv[1] if len(sys.argv) > 1
            else r"F:\Retro and Emulation\ECWolf_RMST")
