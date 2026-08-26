#!/usr/bin/env python3
"""Emit wolfdata/sndprio.txt: the priority behind every Wolf sound.

Wolf does not mix. ID_SD.C keeps ONE digitized sound and ONE AdLib sound
alive at a time, and SD_PlaySound refuses a new one outright when its
priority is lower than what is already playing:

    if (s->priority < DigiPriority)     // ID_SD.C:2169 (digi slot)
        return(false);                  // ID_SD.C:2185 (AdLib slot)

so a quiet sound never truncates a loud one - it simply never plays.
The priority is a word in every AdLib sound chunk's header (SoundCommon:
u32 length, u16 priority), read even for sounds played digitised, and
DigiPriority/SoundPriority fall back to 0 when the sound ends
(SDL_DigitizedDone, ID_SD.C:1184; SDL_SoundFinished, ID_SD.C:48).

Rows: <SNDINFO logical name> <priority> <slot>, slot 0 = digitised
(wolfdigimap), 1 = AdLib. Names SNDINFO defines that are not Wolf
sounds (the engine's menu/* set) are left out and stay ungated.
"""
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from wolf_common import ROOT
from make_assets import DIGI_NAMES, digimap_for_build

SET = "sod" if "sod" in sys.argv[1:] else "wl6"
SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"
AUDIO_H = "AUDIOSOD.H" if SET == "sod" else "AUDIOWL6.H"
ADLIB = ROOT / "build" / "audio" / SET / "adlib"
ASSETS = ROOT / "build" / ("assets_sod" if SET == "sod" else "assets")


def sound_numbers():
    """sound-enum name -> chunk index, from the build's AUDIO*.H."""
    text = (SRC / AUDIO_H).read_text(errors="replace")
    return {nm: int(n)
            for nm, n in re.findall(r"(\w+SND)\s*,?\s*//\s*(\d+)", text)}


def priorities(numbers):
    """sound-enum name -> priority word from its AdLib chunk header."""
    out = {}
    for name, num in numbers.items():
        chunk = ADLIB / f"SFX{num:03d}.bin"
        if not chunk.exists():
            continue
        head = chunk.read_bytes()[:6]
        if len(head) < 6:
            continue
        out[name] = struct.unpack("<IH", head)[1]
    return out


def main():
    numbers = sound_numbers()
    prio = priorities(numbers)
    digi_enum = {v: k for k, v in DIGI_NAMES.items()}   # lump name -> enum
    digitised = {digi_enum[lump] for _, lump in digimap_for_build()
                 if lump in digi_enum}

    rows, unmapped = [], []
    for line in (ROOT / "src" / "SNDINFO").read_text(errors="replace").splitlines():
        m = re.match(r'\s*([\w/]+)\s+"sounds/([\w.]+)\.wav"', line)
        if not m:
            continue
        logical, stem = m.group(1), m.group(2)
        if logical.startswith("menu/"):
            continue                        # engine UI, not a Wolf SFX
        # AdLib lumps are packed as the enum name lowercased; digitised
        # ones carry our own short name, and the line names the enum.
        enum = None
        if stem.upper() in prio:
            enum = stem.upper()
        elif stem in digi_enum:
            enum = digi_enum[stem]
        else:
            c = re.search(r"//\s*(\w+SND)", line)
            if c and c.group(1) in prio:
                enum = c.group(1)
        if enum is None or enum not in prio:
            unmapped.append(logical)
            continue
        rows.append(f"{logical} {prio[enum]} {0 if enum in digitised else 1}")

    (ASSETS / "wolfdata").mkdir(parents=True, exist_ok=True)
    (ASSETS / "wolfdata" / "sndprio.txt").write_text("\n".join(rows) + "\n")
    print(f"{SET}: {len(rows)} sound priorities"
          + (f", {len(unmapped)} ungated ({', '.join(unmapped[:6])})"
             if unmapped else ""))


if __name__ == "__main__":
    main()
