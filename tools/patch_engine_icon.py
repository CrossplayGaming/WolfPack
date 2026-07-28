#!/usr/bin/env python3
"""Brand the engine exe with the WolfPack icon, in place.

The window/taskbar/Explorer icon is the exe's RT_ICON/RT_GROUP_ICON
resources. Rebuilding a PE resource section is fragile, so this works
strictly IN PLACE: every replacement image is encoded to fit inside
the existing slot (padded with zeros), the resource Size fields and
the group header's BytesInRes are updated, and nothing moves. Slots
whose replacement cannot fit keep more compressed encodings until it
does. Idempotent: a fingerprint of the source art is written into the
group header's reserved word.

Source art: import/bootlogo.png (the committed WolfPack badge).
engine/ is a local, gitignored copy - nothing patched is committed.
"""
import io
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / "engine" / "uzdoom.exe"
ART = (ROOT / "import" / "icon.png"
       if (ROOT / "import" / "icon.png").exists()
       else ROOT / "import" / "bootlogo.png")


def art_master():
    im = Image.open(ART).convert("RGBA")
    bb = im.split()[3].getbbox()
    im = im.crop(bb)
    side = max(im.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return sq


def dib_icon(img):
    """Classic 32bpp DIB icon entry (BITMAPINFOHEADER + BGRA + mask)."""
    w, h = img.size
    header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0,
                         w * h * 4, 0, 0, 0, 0)
    px = img.load()
    xor = bytearray()
    for y in range(h - 1, -1, -1):
        for x in range(w):
            r, g, b, a = px[x, y]
            xor += bytes((b, g, r, a))
    maskrow = (w + 31) // 32 * 4
    mask = bytearray()
    for y in range(h - 1, -1, -1):
        row = bytearray(maskrow)
        for x in range(w):
            if px[x, y][3] < 128:
                row[x // 8] |= 0x80 >> (x % 8)
        mask += row
    return bytes(header) + bytes(xor) + bytes(mask)


def png_icon(img, budget):
    """PNG entry, quantized down until it fits the slot budget."""
    for colors in (0, 256, 128, 64, 32, 16):
        buf = io.BytesIO()
        if colors:
            q = img.quantize(colors, method=Image.FASTOCTREE)
            q.save(buf, "PNG", optimize=True)
        else:
            img.save(buf, "PNG", optimize=True)
        data = buf.getvalue()
        if len(data) <= budget:
            return data
    return None


def main():
    if not EXE.exists() or not ART.exists():
        return
    import pefile
    pe = pefile.PE(str(EXE))
    rt_icon = rt_group = None
    for e in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if e.id == pefile.RESOURCE_TYPE["RT_ICON"]:
            rt_icon = e
        if e.id == pefile.RESOURCE_TYPE["RT_GROUP_ICON"]:
            rt_group = e
    if rt_icon is None or rt_group is None:
        print("icon patch: no icon resources found")
        return
    data = bytearray(EXE.read_bytes())

    fp = zlib.crc32(ART.read_bytes()) & 0xFFFF

    grp = rt_group.directory.entries[0].directory.entries[0]
    goff = pe.get_offset_from_rva(grp.data.struct.OffsetToData)
    reserved, gtype, count = struct.unpack_from("<HHH", data, goff)
    if reserved == fp:
        return                              # already this art
    entries = {}
    for i in range(count):
        w, h, cc, res, planes, bpp, size, iid = struct.unpack_from(
            "<BBBBHHIH", data, goff + 6 + i * 14)
        entries[iid] = (w or 256, h or 256, goff + 6 + i * 14, size)

    backup = EXE.with_suffix(".exe.orig")
    if not backup.exists():
        backup.write_bytes(bytes(data))

    master = art_master()
    slots = {}
    for icon in rt_icon.directory.entries:
        lang = icon.directory.entries[0]
        slots[icon.id] = (pe.get_offset_from_rva(
            lang.data.struct.OffsetToData), lang.data.struct.Size, lang)

    # resolve every file offset BEFORE closing the mapping, then close
    # so the in-place write can open the file
    for iid in list(slots):
        off, size, lang = slots[iid]
        slots[iid] = (off, size, lang.data.struct.get_file_offset())
    pe.close()

    patched = 0
    for iid, (w, h, ghdr, gsize) in entries.items():
        if iid not in slots:
            continue
        off, budget, soff = slots[iid]
        img = master.resize((w, h), Image.LANCZOS)
        new = dib_icon(img)
        if len(new) > budget:
            new = png_icon(img, budget)
        if new is None:
            print(f"icon patch: slot {iid} ({w}px) too small, kept")
            continue
        data[off:off + len(new)] = new
        data[off + len(new):off + budget] = bytes(budget - len(new))
        struct.pack_into("<I", data, ghdr + 8, len(new))
        # resource entry Size field lives in the file too
        struct.pack_into("<I", data, soff + 4, len(new))
        patched += 1
    struct.pack_into("<H", data, goff, fp)   # fingerprint = done
    EXE.write_bytes(bytes(data))
    print(f"icon patch: branded {patched}/{count} icon slots")


if __name__ == "__main__":
    main()
