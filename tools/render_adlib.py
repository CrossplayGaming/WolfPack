#!/usr/bin/env python3
"""Render AdLib audio to WAV via OPL2 emulation (pyopl / DOSBox core).

- SFX: AdLibSound chunks (extract_audio.py outputs) — header:
  u32 length, u16 priority, 16-byte Instrument (mChar cChar mScale cScale
  mAttack cAttack mSus cSus mWave cWave nConn voice mode pad[3]), u8 block,
  then `length` bytes of F-number lows played at 140 Hz on channel 0:
  0 = key off, else regA0=byte, regB0=((block&7)<<2)|0x20 (ID_SD.C
  SDL_ALPlaySound/SDL_AlSetFXInst — modifier op 0x00, carrier op 0x03).
- Music: IMF (WLF variant, u16 length header) — [u8 reg, u8 val, u16 delay]
  entries at 700 Hz.

Outputs: build/audio/wl6/sfx/<NAME>.wav (sound-enum names from AUDIOWL6.H)
and build/audio/wl6/music_wav/<SHORT>.wav for tracks passed via --music.
"""
import re
import struct
import sys
import wave
from pathlib import Path

import pyopl

from wolf_common import ROOT

SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"
# per game set: Spear has its own sound enum (AUDIOSOD.H) and its own
# AdLib chunks, so both the names and the rendered output differ
SET = "sod" if "sod" in sys.argv[1:] else "wl6"
AUD = ROOT / "build" / "audio" / SET
AUDIO_H = "AUDIOSOD.H" if SET == "sod" else "AUDIOWL6.H"
RATE = 44100


class OPL:
    def __init__(self):
        self.o = pyopl.opl(RATE, 2, 1)
        self.frac = 0.0

    def w(self, reg, val):
        self.o.writeReg(reg, val)

    def render(self, seconds, out):
        n = int(seconds * RATE)
        # pyopl renders in bounded chunks
        CH = 512
        while n > 0:
            take = min(CH, n)
            buf = bytearray(take * 2)
            self.o.getSamples(buf)
            out += buf
            n -= take


def sound_enum():
    text = (SRC / AUDIO_H).read_text(errors="replace")
    names = {}
    for name, num in re.findall(r"(\w+SND)\s*,?\s*//\s*(\d+)", text):
        names[int(num)] = name
    return names


def render_sfx(idx, name):
    binp = AUD / "adlib" / f"SFX{idx:03d}.bin"
    if not binp.exists():
        return False
    raw = binp.read_bytes()
    (length,) = struct.unpack_from("<I", raw, 0)
    inst = raw[6:22]
    block = raw[22]
    data = raw[23:23 + length]
    if not data:
        return False

    o = OPL()
    # SDL_AlSetFXInst: modifier op 0, carrier op 3
    m, c = 0, 3
    mChar, cChar, mScale, cScale, mAtk, cAtk, mSus, cSus, mWave, cWave = inst[:10]
    o.w(0x20 + m, mChar); o.w(0x40 + m, mScale); o.w(0x60 + m, mAtk)
    o.w(0x80 + m, mSus);  o.w(0xE0 + m, mWave)
    o.w(0x20 + c, cChar); o.w(0x40 + c, cScale); o.w(0x60 + c, cAtk)
    o.w(0x80 + c, cSus);  o.w(0xE0 + c, cWave)
    o.w(0xC0, 0)                    # feedback/connection
    alBlock = ((block & 7) << 2) | 0x20

    out = bytearray()
    step = 1.0 / 140.0
    for b in data:
        if b == 0:
            o.w(0xB0, 0)            # key off
        else:
            o.w(0xA0, b)
            o.w(0xB0, alBlock)
        o.render(step, out)
    o.w(0xB0, 0)
    o.render(0.05, out)             # release tail

    outdir = AUD / "sfx"
    outdir.mkdir(exist_ok=True)
    with wave.open(str(outdir / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(out))
    return True


def render_imf(imf_path, out_path):
    raw = imf_path.read_bytes()
    (dlen,) = struct.unpack_from("<H", raw, 0)
    data = raw[2:2 + dlen] if dlen else raw[2:]
    o = OPL()
    out = bytearray()
    for i in range(0, len(data) - 3, 4):
        reg, val, delay = data[i], data[i + 1], struct.unpack_from("<H", data, i + 2)[0]
        o.w(reg, val)
        if delay:
            o.render(delay / 700.0, out)
    o.render(0.1, out)
    # FLAC via soundfile (this libsndfile's OGG/Vorbis encoder writes
    # empty containers; FLAC is core and GZDoom plays it)
    import numpy, soundfile
    samples = numpy.frombuffer(bytes(out), dtype=numpy.int16)
    soundfile.write(str(out_path.with_suffix(".flac")), samples, RATE,
                    format="FLAC")


def main():
    names = sound_enum()
    n = 0
    for idx, name in sorted(names.items()):
        if (AUD / "sfx" / f"{name}.wav").exists():
            continue
        if render_sfx(idx, name):
            n += 1
    print(f"rendered {n} AdLib SFX", flush=True)

    if "--music" in sys.argv:
        outdir = AUD / "music_wav"
        outdir.mkdir(exist_ok=True)
        for imf in sorted((AUD / "music").glob("*.imf")):
            short = imf.stem.replace("_MUS", "")[:8]
            if (outdir / f"{short}.flac").exists():
                continue
            render_imf(imf, outdir / f"{short}.wav")
            print(f"  music {short}", flush=True)


if __name__ == "__main__":
    main()
