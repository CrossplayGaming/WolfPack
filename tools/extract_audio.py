#!/usr/bin/env python3
"""Phase 1: extract AUDIOT (PC/AdLib sound effects, IMF music).

AUDIOHED = u32 offsets into AUDIOT. Chunk layout and music track names are
parsed from the source headers (AUDIOWL6.H / AUDIOSOD.H): PC sounds
[0, STARTADLIBSOUNDS), AdLib sounds [STARTADLIBSOUNDS, STARTDIGISOUNDS)
(AdLibSound struct: u32 length, u16 priority, 16b instrument, u8 block, data),
digi placeholders, then music at STARTMUSIC (chunk = u16 length + IMF stream).

Outputs (build/audio/<set>/): music/<NAME>.imf (playable IMF, the u16-length
'WLF' variant at 700 Hz), adlib/SFXnnn.bin raw chunks, manifest.json.
"""
import json
import re
import struct
import sys
from pathlib import Path

from wolf_common import ROOT, find_data

SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"
OUT = ROOT / "build" / "audio"


def parse_header(name):
    text = (SRC / name).read_text(errors="replace")
    consts = {k: int(v) for k, v in
              re.findall(r"#define\s+(START\w+|NUMSOUNDS|NUMSNDCHUNKS)\s+(\d+)", text)}
    music = [m for m in re.findall(r"^\s*(\w+_MUS),", text, re.M)]
    return consts, music


def extract_set(setname, header, hed_path, t_path):
    consts, music = parse_header(header)
    startadlib = consts["STARTADLIBSOUNDS"]
    startdigi = consts["STARTDIGISOUNDS"]
    startmusic = consts["STARTMUSIC"]

    hed = hed_path.read_bytes()
    offsets = struct.unpack_from(f"<{len(hed) // 4}I", hed, 0)
    data = t_path.read_bytes()

    out = OUT / setname
    (out / "music").mkdir(parents=True, exist_ok=True)
    (out / "adlib").mkdir(parents=True, exist_ok=True)

    def chunk(i):
        return data[offsets[i]:offsets[i + 1]]

    nadlib = 0
    for i in range(startadlib, startdigi):
        c = chunk(i)
        if len(c) > 7:
            (out / "adlib" / f"SFX{i - startadlib:03d}.bin").write_bytes(c)
            nadlib += 1

    tracks = []
    for m, name in enumerate(music):
        c = chunk(startmusic + m)
        if len(c) < 2:
            continue
        (imf_len,) = struct.unpack_from("<H", c, 0)
        (out / "music" / f"{name}.imf").write_bytes(c)  # keep WLF-style length header
        tracks.append({"index": m, "name": name, "imf_bytes": imf_len})

    (out / "manifest.json").write_text(json.dumps(
        {"set": setname, "consts": consts, "adlib_sfx": nadlib,
         "music": tracks}, indent=1))
    print(f"{setname}: {nadlib} AdLib SFX, {len(tracks)} music tracks "
          f"({', '.join(t['name'] for t in tracks[:5])} ...)")


def main():
    done = 0
    for setname, ext, header in (("wl6", "WL6", "AUDIOWL6.H"),
                                 ("sod", "SOD", "AUDIOSOD.H")):
        hits = find_data(ext)
        if "AUDIOHED" in hits and "AUDIOT" in hits:
            extract_set(setname, header, hits["AUDIOHED"], hits["AUDIOT"])
            done += 1
    if not done:
        sys.exit("no AUDIOHED/AUDIOT found")


if __name__ == "__main__":
    main()
