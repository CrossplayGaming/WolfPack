#!/usr/bin/env python3
"""Phase 1: extract VSWAP (wall textures, sprites, digitized sounds).

VSWAP header (ID_PM.C): u16 ChunksInFile, u16 PMSpriteStart, u16 PMSoundStart,
u32 offsets[n], u16 lengths[n].
  chunks [0, spritestart)          64x64 column-major 8-bit wall textures
  chunks [spritestart, soundstart) sparse-column compressed sprites
  chunks [soundstart, n-1)         digitized sound pages (4096 b), 8-bit
                                   unsigned mono @ 7000 Hz (ID_SD.C:566)
  chunk  n-1                       table of {u16 startpage, u16 bytelength}

Outputs (build/, gitignored): walls/sprites as paletted PNG (palette from the
source release's GAMEPAL.OBJ), sounds as WAV, plus manifest.json.
"""
import json
import struct
import sys
import wave
from pathlib import Path

from PIL import Image

from wolf_common import ROOT, find_data, load_palette

OUT = ROOT / "build" / "vswap"
DIGI_RATE = 7000  # ID_SD.C:566 — SSI timer 1000000/7000


def parse_header(data):
    n, spritestart, soundstart = struct.unpack_from("<3H", data, 0)
    offsets = struct.unpack_from(f"<{n}I", data, 6)
    lengths = struct.unpack_from(f"<{n}H", data, 6 + 4 * n)
    return n, spritestart, soundstart, offsets, lengths


def decode_wall(chunk):
    """64x64 column-major -> PIL paletted image."""
    img = Image.new("P", (64, 64))
    px = img.load()
    for x in range(64):
        col = chunk[x * 64:(x + 1) * 64]
        for y in range(64):
            px[x, y] = col[y]
    return img


def decode_sprite(chunk):
    """Sparse-column sprite -> (image, leftpix, rightpix). Index 255 = transparent
    marker here (Wolf sprites never use 255; asserted)."""
    leftpix, rightpix = struct.unpack_from("<2H", chunk, 0)
    width = rightpix - leftpix + 1
    colofs = struct.unpack_from(f"<{width}H", chunk, 4)
    img = Image.new("P", (64, 64))
    px = img.load()
    for x in range(64):
        for y in range(64):
            px[x, y] = 255
    for cx, ofs in enumerate(colofs):
        i = ofs
        while True:
            (endy,) = struct.unpack_from("<H", chunk, i)
            if endy == 0:
                break
            (pool,) = struct.unpack_from("<h", chunk, i + 2)
            (starty,) = struct.unpack_from("<H", chunk, i + 4)
            for y in range(starty // 2, endy // 2):
                val = chunk[(pool + y) & 0xFFFF]
                assert val != 255, "sprite uses palette index 255"
                px[leftpix + cx, y] = val
            i += 6
    return img


def save_png(img, pal, path, transparent=None):
    flat = []
    for r, g, b in pal:
        flat += [r, g, b]
    img.putpalette(flat)
    if transparent is not None:
        img.save(path, transparency=transparent)
    else:
        img.save(path)


def extract_set(setname, path, pal):
    data = path.read_bytes()
    n, spritestart, soundstart, offsets, lengths = parse_header(data)
    out = OUT / setname
    for sub in ("walls", "sprites", "sounds"):
        (out / sub).mkdir(parents=True, exist_ok=True)

    def chunk(i):
        return data[offsets[i]:offsets[i] + lengths[i]]

    nwalls = nsprites = 0
    for i in range(spritestart):
        c = chunk(i)
        if not c:
            continue
        assert len(c) == 4096, f"wall chunk {i}: {len(c)} bytes"
        save_png(decode_wall(c), pal, out / "walls" / f"WALL{i:03d}.png")
        nwalls += 1
    for i in range(spritestart, soundstart):
        c = chunk(i)
        if not c:
            continue
        save_png(decode_sprite(c), pal, out / "sprites" / f"SPR{i - spritestart:03d}.png",
                 transparent=255)
        nsprites += 1

    # digitized sound table lives in the final chunk
    table = chunk(n - 1)
    ndigi = len(table) // 4
    sounds = []
    for s in range(ndigi):
        startpage, bytelen = struct.unpack_from("<2H", table, s * 4)
        page = soundstart + startpage
        raw = bytearray()
        while len(raw) < bytelen and page < n - 1:
            raw += chunk(page)
            page += 1
        raw = raw[:bytelen]
        if not raw:
            continue
        wav_path = out / "sounds" / f"DIGI{s:03d}.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(1)
            w.setframerate(DIGI_RATE)
            w.writeframes(bytes(raw))
        sounds.append({"index": s, "bytes": bytelen})

    manifest = {"set": setname, "chunks": n, "spritestart": spritestart,
                "soundstart": soundstart, "walls": nwalls,
                "sprites": nsprites, "digisounds": len(sounds)}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"{setname}: {nwalls} walls, {nsprites} sprites, {len(sounds)} digitized sounds")
    return manifest


def main():
    pal = load_palette()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "palette.json").write_text(json.dumps(pal))
    done = 0
    for setname, ext in (("wl6", "WL6"), ("sod", "SOD")):
        hits = find_data(ext)
        if "VSWAP" in hits:
            extract_set(setname, hits["VSWAP"], pal)
            done += 1
    if not done:
        sys.exit("no VSWAP found")


if __name__ == "__main__":
    main()
