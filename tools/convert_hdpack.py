#!/usr/bin/env python3
"""Convert the ECWolf RMST HD pack into WolfPack addon pk3s.

Runs on the USER'S machine against THEIR downloaded copy of the pack -
WolfPack ships only this converter and the name map
(docs/data/hdpack_map.json), never the art. Credit: RMST ("ECWolf
Unofficial Remaster") by its author on ModDB; the original readme is
copied into the output pack.

    python tools/convert_hdpack.py <RMST folder or ECWolf_RMST.pk3>

Produces:
    dist/hdtex.pk3      Wolf3D walls, statics, enemies, weapons, HUD
    dist/hdtex_sod.pk3  the same for Spear of Destiny
    dist/hdsfx.pk3      remastered sounds (shared by both games)

Two texture packs, not one: the games reuse the same WALLnnn and
sprite numbers for different art (Spear's tile 50 is WALL098, a door
in Wolf3D), so a single pack would put Spear's cobblestone on Wolf3D's
doors. The launcher loads whichever matches the game being started.

Every mapping is AUTHORED, never guessed: ECWolf's own xlat tables and
DECORATE states are joined against our generated tables, and the pack
maps its art onto ECWolf's names in its own TEXTURES lump. Art is then
checked by image against our extracted originals, which catches the
off-by-one class of error - a systematic slip lands the argmin on a
near-exact match, and that is still withheld. A merely-drifted repaint
warns and ships. Sounds cannot be checked this way at all: the pack
replaces recordings rather than cleaning them up, so their length and
shape say nothing (see sound_report).
"""
import io
import json
import re
import sys
import wave
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MAP = json.loads((ROOT / "docs/data/hdpack_map.json").read_text())

GAMES = {                      # game -> (our sprite dir, our wall dir)
    "wl6": ("build/assets", "build/vswap/wl6/walls"),
    "sod": ("build/assets_sod", "build/vswap/sod/walls"),
}

# Our SNDINFO logical names <- RMST wav basenames, from the pack's OWN
# SNDINFO (its logical-name -> wav join is authored data) and, for the
# enemy voices it ships commented out, from matching the two sides'
# actors role by role. Whatever is left over is reported by name at
# the end of a run - those are slots this engine does not have (extra
# sight variants, pain grunts Wolf3D never had, other mods' sounds).
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
    # Enemy voices. The pack ships these but leaves them commented out
    # in its own SNDINFO; Eric asked for the whole pack, so they are
    # wired up by ROLE - every line below pairs the sound one actor
    # plays on our side with the sound the SAME actor plays on theirs
    # (their DECORATE attacksound/seesound/deathsound resolved through
    # their SNDINFO, ours from bosses.zs/enemies.zs).
    "wolf/halt": "halt",                     # guard sight
    "wolf/nazifire": "GUNSHT",               # guard + officer attack
    "wolf/spion": "ACHTNG2",                 # officer sight
    "wolf/schutzad": "SHUTZSTF",             # SS sight
    "wolf/ssfire": "GUNSHT2",                # SS attack
    "wolf/dogbark": "WOOF", "wolf/dogattack": "bark",
    "wolf/dogdeath": "yelp",
    "wolf/slurpie": "SLURPIE",
    # death cries: 1 and 2 are the guard's, the rest are the shared
    # random pool (officer, SS and mutant deaths in the remaster).
    # DEATHSCREAM6 is the secret-level gag our SecretScream plays and
    # the pack names its remaster of it DSFART.
    "wolf/death1": "die1", "wolf/death2": "die2",
    "wolf/death3": "EDIE", "wolf/death4": "HEIFER",
    "wolf/death5": "MEINGUT", "wolf/death6": "DSFART",
    "wolf/death7": "SSHEIFR", "wolf/death8": "MUTDIE",
    "wolf/death9": "SSMUM",
    "wolf/neinsovas": "EDIE", "wolf/leben": "LEIBEN",
    "wolf/ahhhg": "EDIE2",
    # bosses, each pinned to the actor that plays it
    "wolf/gutentag": "HNSIT", "wolf/mutti": "HNDIE",     # Hans
    "wolf/kein": "GRTSIT", "wolf/mein": "GRTDTH",        # Gretel
    "wolf/schabbsha": "SCSIT", "wolf/meingott": "SCDIE",  # Schabbs
    "wolf/eine": "BOSS4", "wolf/donner": "BOSDIE",       # Giftmacher
    "wolf/erlauben": "BOSS2", "wolf/rose": "BOSDIE",     # Fat Face
    "wolf/tothund": "SCSIT", "wolf/hitlerha": "THUD",    # Fake Hitler
    "wolf/die": "HITLSIT", "wolf/scheist": "HITLSIT2",   # Mecha Hitler
    "wolf/eva": "EVAAUF", "wolf/mechstep": "MECHSTEP",   # Hitler
    "wolf/bossfire": "BIGGUN",                           # boss chaingun
    "wolf/leveldone": "EXITBUT",                         # exit switch
    # Spear bosses
    "sod/transsight": "HNSIT", "sod/transdeath": "HNDIE",
    "sod/willsight": "BOSS3", "sod/uberdeath": "UBDIE",
    "sod/knightsight": "DKSIT", "sod/knightdeath": "DKFALL",
    "sod/knightmissile": "DKMISS",
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


# ---------------------------------------------------------------------------
# image comparison

_thumbs = {}


def _thumb(img):
    """32x32 thumbnail with transparency flattened onto one fixed
    backdrop and cropped to the art. Going straight to RGB is wrong for
    a palette sprite: PIL fills transparent pixels with whatever color
    sits at that index, so a mostly-empty sprite (the knife is ~95%
    air) gets compared on its BACKGROUND - which is how the knife once
    lost its argmin to a Pac-Man ghost easter egg. And an uncropped
    canvas compares PLACEMENT rather than art when the two packs frame
    on different canvas sizes."""
    img = img.convert("RGBA")
    box = img.getbbox()
    if box:
        img = img.crop(box)
    bg = Image.new("RGBA", img.size, (0, 255, 0, 255))
    return Image.alpha_composite(bg, img).convert("RGB")         .resize((32, 32)).load()


def _thumb_set(kind, game):
    key = (kind, game)
    if key in _thumbs:
        return _thumbs[key]
    sprites, walls = GAMES[game]
    d = ROOT / (walls if kind == "wall" else sprites + "/" + kind)
    _thumbs[key] = {f.stem: _thumb(Image.open(f)) for f in d.glob("*.png")}
    return _thumbs[key]


def _dist(pa, pb):
    return sum(abs(pa[x, y][c] - pb[x, y][c])
               for x in range(0, 32, 2) for y in range(0, 32, 2)
               for c in range(3))


def wall_sibling(name):
    """The other face of the same wall: our WALLnnn pairs are the light
    and dark rendering of one texture, so an argmin that lands on the
    sibling is agreement, not a mismatch."""
    m = re.match(r"WALL(\d+)$", name)
    if not m:
        return ""
    n = int(m.group(1))
    return f"WALL{n - 1 if n % 2 else n + 1:03d}"


def verify(hd_png, our_name, kind, game, family=""):
    """RELATIVE check: a remaster legitimately differs from the
    original in absolute pixels, so absolute thresholds condemned half
    the (correct) map. The mapping is wrong only if some OTHER original
    matches the HD art clearly better than the mapped one.

    `family` names a group of lumps whose members are interchangeable
    answers - a weapon's five view frames, an enemy's poses. The HD
    idle art can resemble our recoil frame more than our idle frame,
    and that says nothing about whether the right weapon was picked;
    which frame gets which art comes from the authored joins."""
    thumbs = _thumb_set(kind, game)
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
    if kind == "wall" and best_name == wall_sibling(our_name):
        return d_target, None
    if best_name == our_name:
        return d_target, None
    # Two tiers, because every join here is now AUTHORED (ECWolf's own
    # xlat/decorate against our generated tables) rather than guessed.
    # A systematic error - the off-by-one class this check exists to
    # kill - lands the argmin on a near-exact match; a repaint that
    # merely wandered from the original lands it in the same
    # neighbourhood as the intended lump. Withholding at the second
    # tier threw away correct art (a remastered pot really does look
    # like a different pot), so that tier now warns instead.
    if best_d < d_target * 0.45:
        return d_target, f"argmin is {best_name} ({best_d} vs {d_target})"
    if best_d < d_target * 0.75:
        return d_target, f"WARN argmin is {best_name} " \
                         f"({best_d} vs {d_target}) - shipped anyway"
    return d_target, None


def parse_textures(text):
    """RMST TEXTURES entries: name -> (kind, width, height, body)."""
    out = {}
    for m in re.finditer(
            r'(Texture|Sprite|Graphic)\s+(?:Optional\s+)?(\w+),\s*(\d+),'
            r'\s*(\d+)\s*\{([^}]*)\}', text, re.I):
        out[m.group(2).upper()] = (m.group(1), int(m.group(3)),
                                   int(m.group(4)), m.group(5))
    return out


# ---------------------------------------------------------------------------
# passes


class Pack:
    """One output pk3 plus its generated TEXTURES lump."""

    def __init__(self, path, game):
        self.zip = zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED)
        self.game = game
        self.lump = ["// GENERATED by convert_hdpack.py from ECWolf RMST"
                     " - art (c) its author, converted locally"]
        self.written = set()
        self.n = self.suspect = self.skipped = 0

    def art(self, folder, name, data):
        if (folder, name) not in self.written:
            self.zip.writestr(f"{folder}/{name}.png", data)
            self.written.add((folder, name))

    def close(self, readme):
        self.zip.writestr("TEXTURES.hd", "\n".join(self.lump) + "\n")
        if readme:
            self.zip.writestr("RMST_README.txt", readme)
        self.zip.close()


def walls(z, names, pack):
    for ec, ours in sorted(MAP[pack.game]["walls"].items()):
        path = f"textures/default/{ec}.png"
        if path not in names:
            pack.skipped += 1
            continue
        data = z.read(path)
        _, err = verify(data, ours, "wall", pack.game)
        if err:
            print(f"  {'' if err.startswith('WARN') else 'SUSPECT '}"
                  f"wall {ec} -> {ours}: {err}")
            if not err.startswith("WARN"):
                pack.suspect += 1
                continue
        pack.art("patches", ours, data)
        pack.lump.append(f"Texture {ours}, 128, 128 {{ XScale 2 YScale 2 "
                         f"Patch {ours}, 0, 0 }}")
        pack.n += 1


def flat_sprites(z, names, tex, pack, table, folder="sprites/default"):
    """Statics, pickups, ghosts, projectiles: art whose ECWolf name
    already identifies the object, one or a few frames each."""
    for ec, ours in sorted(table.items()):
        for n in names:
            m = re.match(rf"{folder}/{ec}(\w\d)\.png$", n)
            if not m:
                continue
            frame, data = m.group(1), z.read(n)
            dst = f"{ours}{frame}"
            if dst not in _thumb_set("sprites", pack.game):
                # our art for a rotation the original drew only once
                # (or an object this game does not have at all)
                alt = f"{ours}{frame[0]}0"
                # our lump is unrotated: take their FRONT view for it
                # and drop the other seven, or the last rotation
                # written wins (the rocket ended up facing away)
                if alt not in _thumb_set("sprites", pack.game)                         or frame[1] not in "01":
                    pack.skipped += 1
                    continue
                dst = alt
            _, err = verify(data, dst, "sprites", pack.game,
                            family=ours if ec == ours else "")
            if err:
                print(f"  {'' if err.startswith('WARN') else 'SUSPECT '}"
                      f"sprite {ec}{frame} -> {dst}: {err}")
                if not err.startswith("WARN"):
                    pack.suspect += 1
                    continue
            pack.art("sprites", dst, data)
            td = tex.get(f"{ec}{frame}")
            if td:
                _, w, h, body = td
                body = re.sub(rf"\b{ec}{frame}\b", dst, body)
                pack.lump.append(f"Sprite {dst}, {w}, {h} {{{body}}}")
            pack.n += 1


def enemies(z, names, tex, pack):
    """Enemy poses, all eight rotations.

    The pose join comes from gen_hdenemies.py (ECWolf's DECORATE state
    labels against ours); this only has to place the rotations. Where
    the pack has a single rot-0 image and our sprite is rotated - a
    pain frame the original drew once - the one image goes to all eight
    of ours, because a lump cannot have rot 0 and rots 1-8 at once."""
    ours_dir = ROOT / GAMES[pack.game][0] / "sprites"
    checked = set()
    for ec, ours in sorted(MAP["enemies"].items()):
        rots = {}
        for n in names:
            m = re.match(rf"sprites/\w+/\w+/{ec}(\d)\.png$", n)
            if m:
                rots[m.group(1)] = n
        if not rots:
            continue
        # ours is sprite+frame (GRDS + A); what is left is the rotation
        targets = sorted(p.stem[5:] for p in ours_dir.glob(f"{ours}?.png"))
        if not targets:
            continue                     # e.g. Spear-only enemy in Wolf3D
        family = ours[:3]
        if family not in checked:        # one image check per enemy
            checked.add(family)
            probe = rots.get("1") or rots.get("0")
            _, err = verify(z.read(probe), f"{ours}{targets[0]}",
                            "sprites", pack.game, family=family)
            if err:
                # advisory only: the pose join is authored on both
                # sides, and lookalike bosses (Gift vs Fat Face, same
                # white coat) trip the argmin without being wrong
                print(f"  WARN enemy {ec} -> {ours}: {err}")
        for t in targets:
            src = rots.get(t) or rots.get("0") or rots.get("1")
            data = z.read(src)
            dst = f"{ours}{t}"
            pack.art("sprites", dst, data)
            key = Path(src).stem.upper()
            td = tex.get(key)
            if td:
                _, w, h, body = td
                body = re.sub(rf"\b{key}\b", dst, body, flags=re.I)
                pack.lump.append(f"Sprite {dst}, {w}, {h} {{{body}}}")
            pack.n += 1


def weapons(z, names, tex, pack):
    """First-person weapon frames.

    The pack draws its five view frames from three or four painted
    images, animating the rest with per-frame vertical offsets (the gun
    rising with recoil), and it publishes that join in its own TEXTURES
    lump - so the frame->art mapping is read, never guessed. Geometry
    is copied VERBATIM from those entries: the pack was authored
    against ECWolf, whose view-sprite placement matches this engine's,
    so its own numbers put each weapon where its author intended.
    Deriving placement instead (fitting their art onto our sprite's
    bounding box) was tried first and misjudged both size and height,
    because their art is cropped at the canvas edge where ours floats
    inside a larger frame."""
    for ec, ours in sorted(MAP["weapons"].items()):
        frames = {}
        for fr in "ABCDE":
            td = tex.get(f"{ec}{fr}0")
            if not td:
                continue
            _, w, h, body = td
            pm = re.search(r"Patch\s+(\w+)", body, re.I)
            if pm:
                frames[fr] = (pm.group(1), w, h, " ".join(body.split()))
        if "A" not in frames:
            print(f"  skipped weapon {ec}: no idle frame in the pack")
            continue
        patch_a = frames["A"][0]
        _, err = verify(z.read(f"sprites/default/{patch_a}.png"),
                        f"{ours}A0", "sprites", pack.game, family=ours)
        if err:
            print(f"  SUSPECT weapon {ec} -> {ours}: {err}")
            pack.suspect += 1
            continue
        for fr, (patch, w, h, body) in sorted(frames.items()):
            path = f"sprites/default/{patch}.png"
            if path not in names:
                continue
            pack.art("patches", patch, z.read(path))
            pack.lump.append(f"Sprite {ours}{fr}0, {w}, {h} {{{body}}}")
            pack.n += 1


# Their art covers only part of ours: our status bar sits at 1x in a
# 1120-wide canvas that lets it fill an ultrawide screen, while theirs
# is just the 320-wide bar at 2x. The offset was measured by sliding
# their art across ours (best match: width 320 at x=400, dead centre).
INSETS = {"STBAR": (400, 0)}


def graphics(z, names, tex, pack):
    """HUD art. Ours is drawn in 320x200 space at each lump's own size,
    so the HD art needs the scale entry that renders it back down."""
    ours_dir = ROOT / GAMES[pack.game][0] / "graphics"
    for ec, ours in sorted(MAP["graphics"].items()):
        path = f"graphics/{ec}.png"
        if path not in names or not (ours_dir / f"{ours}.png").exists():
            pack.skipped += 1
            continue
        data = z.read(path)
        hd = Image.open(io.BytesIO(data))
        mine = Image.open(ours_dir / f"{ours}.png")
        if ec in INSETS:
            # rebuild our whole canvas at 2x: our own art upscaled for
            # the surround, their art dropped into the region it covers
            x, y = INSETS[ec]
            canvas = mine.convert("RGBA").resize(
                (mine.width * 2, mine.height * 2), Image.NEAREST)
            canvas.paste(hd.convert("RGBA"), (x * 2, y * 2))
            buf = io.BytesIO()
            canvas.save(buf, "PNG")
            data, hd = buf.getvalue(), canvas
        if hd.width % mine.width or hd.height % mine.height:
            print(f"  skipped graphic {ec} -> {ours}: "
                  f"{hd.size} is not a whole multiple of {mine.size}")
            pack.skipped += 1
            continue
        pack.art("patches", ours, data)
        pack.lump.append(
            f"Graphic {ours}, {hd.width}, {hd.height} {{ "
            f"XScale {hd.width // mine.width} "
            f"YScale {hd.height // mine.height} Patch {ours}, 0, 0 }}")
        pack.n += 1


# ---------------------------------------------------------------------------
# sound comparison


def envelope(data, bins=24):
    """(duration, normalized loudness envelope) of a wav."""
    with wave.open(io.BytesIO(data)) as w:
        n, width, rate = w.getnframes(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
        ch = w.getnchannels()
    if not n:
        return 0.0, [0.0] * bins
    step = width * ch
    if width == 1:              # 8-bit wav is unsigned, centred on 128
        samples = [abs(raw[i] - 128) for i in range(0, len(raw), step)]
    else:
        samples = [abs(int.from_bytes(raw[i:i + 2], "little", signed=True))
                   for i in range(0, len(raw), step)]
    per = max(1, len(samples) // bins)
    env = [sum(samples[i * per:(i + 1) * per]) / per for i in range(bins)]
    peak = max(env) or 1.0
    return n / rate, [v / peak for v in env]


def env_dist(a, b):
    return sum(abs(x - y) for x, y in zip(a[1], b[1])) / len(a[1])


def sound_report(theirs, ours):
    """Descriptive only - audio here CANNOT be verified the way art is.

    The remaster does not clean up the original recordings, it replaces
    them: a two-second MP40 burst stands in for a half-second sample,
    and the menu blips are new sounds entirely. So neither duration nor
    loudness shape can decide whether a pairing is right, and a version
    of this that used them as a gate rejected two thirds of a correct
    map. An earlier version went further and used envelopes to DISCOVER
    pairings, which confidently matched the machine gun to BJ's grunt.
    The sound map is therefore role-derived (both sides' authored
    definitions) and this only prints what changed."""
    return f"{ours[0]:.2f}s -> {theirs[0]:.2f}s, env {env_dist(theirs, ours):.2f}"


def sounds(pk3):
    sfx = pk3.parent / "ECWolf_RMST_SFX.pk3"
    if not sfx.exists():
        print("no ECWolf_RMST_SFX.pk3 beside the texture pack - skipping")
        return
    zs = zipfile.ZipFile(sfx)
    wavs = {Path(n).stem.upper(): n for n in zs.namelist()
            if n.lower().endswith(".wav")}
    theirs = {k: envelope(zs.read(v)) for k, v in wavs.items()}

    ours = {}
    for game in GAMES:
        d = ROOT / GAMES[game][0] / "sounds"
        for f in d.glob("*.wav"):
            ours.setdefault(f.stem, envelope(f.read_bytes()))
    logical = {}                 # our SNDINFO name -> our wav stem
    for line in (ROOT / "src/SNDINFO").read_text(errors="replace").splitlines():
        m = re.match(r'\s*([\w/]+)\s+"sounds/([\w.]+)\.wav"', line)
        if m:
            logical[m.group(1)] = m.group(2)

    picked, notes = {}, []
    for name, base in SFX_MAP.items():
        key = base.upper()
        if key not in wavs:
            notes.append(f"{name}: no wav named {base}")
            continue
        picked[name] = key

    left = sorted(set(wavs) - set(picked.values()))
    if left:
        notes.append(f"{len(left)} wavs in the pack have no counterpart "
                     f"in our sound set: {', '.join(w.lower() for w in left)}")

    out, sn = ROOT / "dist/hdsfx.pk3", [
        "// GENERATED: RMST remastered sounds under WolfPack names"]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
        packed = set()
        for name, key in sorted(picked.items()):
            dst = f"sounds/hd_{key.lower()}.wav"
            if dst not in packed:
                o.writestr(dst, zs.read(wavs[key]))
                packed.add(dst)
            sn.append(f'{name}  "{dst}"')
        o.writestr("SNDINFO.hd", "\n".join(sn) + "\n")
    print(f"hdsfx.pk3: {len(picked)} sounds mapped from {len(wavs)} in "
          f"the pack ({len(packed)} distinct wavs)")
    for n in notes:
        print("   ", n)


# ---------------------------------------------------------------------------


def convert(src):
    src = Path(src)
    pk3 = src if src.suffix == ".pk3" else src / "ECWolf_RMST.pk3"
    if not pk3.exists():
        sys.exit(f"{pk3} not found")
    z = zipfile.ZipFile(pk3)
    names = z.namelist()
    tex = {}
    for lump in ("TEXTURES.wall", "TEXTURES.spr", "TEXTURES.gui"):
        if lump in names:
            tex.update(parse_textures(z.read(lump).decode("latin-1")))
    readme = next((z.read(r) for r in names if "readme" in r.lower()), None)

    for game, out in (("wl6", "dist/hdtex.pk3"),
                      ("sod", "dist/hdtex_sod.pk3")):
        if not (ROOT / GAMES[game][0]).exists():
            print(f"{game}: not built, skipping {out}")
            continue
        print(f"== {game}")
        pack = Pack(ROOT / out, game)
        walls(z, names, pack)
        flat_sprites(z, names, tex, pack, MAP[game]["sprites"])
        flat_sprites(z, names, tex, pack, MAP["misc"])
        enemies(z, names, tex, pack)
        weapons(z, names, tex, pack)
        graphics(z, names, tex, pack)
        pack.close(readme)
        print(f"{out}: {pack.n} lumps, {pack.skipped} not in the pack, "
              f"{pack.suspect} suspect mappings withheld")
    sounds(pk3)


if __name__ == "__main__":
    convert(sys.argv[1] if len(sys.argv) > 1
            else r"F:\Retro and Emulation\ECWolf_RMST")
