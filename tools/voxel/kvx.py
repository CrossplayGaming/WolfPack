#!/usr/bin/env python3
"""KVX voxel codec - read and write Ken Silverman's .KVX format.

KVX is the format UZDoom loads voxel models from (via a VOXELDEF lump).
This module is the foundation of the voxel pipeline: everything
downstream produces voxel grids, and this is what turns a grid into
something the engine will actually draw.

FORMAT (little-endian throughout), verified byte-for-byte against
Cheello's Voxel Doom v2.1 (530 models) rather than against a spec:

  per mip level:
    int32  numbytes            length of this level, EXCLUDING this field
    int32  xsiz, ysiz, zsiz    grid dimensions
    int32  xpivot, ypivot, zpivot   pivot, 24.8 fixed point
    int32  xoffset[xsiz+1]     column offsets
    uint16 xyoffset[xsiz][ysiz+1]  offsets within each column
    byte   voxdata[]           slab runs
  ...repeated for each successive mip (each halves the dimensions)...
  byte   palette[768]          6-bit VGA triples, at the very end of the file

Offsets in both tables are relative to the START OF THE XOFFSET TABLE,
and they include the size of the two tables themselves - so
xoffset[0] == (xsiz+1)*4 + xsiz*(ysiz+1)*2 in a well-formed file, and
numbytes == 24 + xoffset[-1]. A voxel column (x,y) occupies
voxdata[xoffset[x] + xyoffset[x][y] : xoffset[x] + xyoffset[x][y+1]].

Each column is a sequence of SLABS - vertical runs of solid voxels:

    uint8 ztop        z of the run's first voxel
    uint8 zleng       number of voxels in the run
    uint8 cullflags   which faces are exposed (see FACE_*)
    uint8 colour[zleng]   palette index per voxel

Only surface voxels need to be stored; interior voxels are invisible and
the renderer never asks for them. Runs are strictly ordered by ztop and
may not overlap.

Self-test:  python tools/voxel/kvx.py --verify <pk3-or-dir>
Cube proof: python tools/voxel/kvx.py --cube out.kvx
"""
import argparse
import struct
import sys
import zipfile
from pathlib import Path

# Which faces of a slab are exposed. The renderer culls the rest.
FACE_LEFT = 0x01    # -x
FACE_RIGHT = 0x02   # +x
FACE_FRONT = 0x04   # -y
FACE_BACK = 0x08    # +y
FACE_TOP = 0x10     # -z
FACE_BOTTOM = 0x20  # +z

HEADER_FIELDS = 6           # xsiz..zpivot
HEADER_BYTES = HEADER_FIELDS * 4
PALETTE_BYTES = 768


class KvxError(Exception):
    """Malformed KVX. Always raised loudly - a silently mis-parsed voxel
    model renders as a plausible-looking wrong shape."""


class Slab:
    """One vertical run of solid voxels within a column."""

    __slots__ = ("ztop", "cull", "colours")

    def __init__(self, ztop, cull, colours):
        self.ztop = ztop
        self.cull = cull
        self.colours = bytes(colours)

    @property
    def zleng(self):
        return len(self.colours)

    def __repr__(self):
        return f"Slab(ztop={self.ztop}, zleng={self.zleng}, cull={self.cull:#04x})"


class KvxMip:
    """One mip level: dimensions, pivot, and a column-major slab grid."""

    def __init__(self, xsiz, ysiz, zsiz, pivot, columns):
        self.xsiz = xsiz
        self.ysiz = ysiz
        self.zsiz = zsiz
        self.pivot = tuple(pivot)       # 24.8 fixed point, as stored
        self.columns = columns          # columns[x][y] -> list[Slab]

    @property
    def pivot_f(self):
        """Pivot in voxel units."""
        return tuple(p / 256.0 for p in self.pivot)

    def slab_count(self):
        return sum(len(col) for row in self.columns for col in row)

    def voxel_count(self):
        return sum(s.zleng for row in self.columns for col in row
                   for s in col)

    # -- parsing ---------------------------------------------------------

    @classmethod
    def parse(cls, buf, start, length):
        """Parse one mip level whose payload begins at `start`."""
        if length < HEADER_BYTES:
            raise KvxError(f"mip at {start} is {length} bytes, too short "
                           f"for a {HEADER_BYTES}-byte header")
        xsiz, ysiz, zsiz, xp, yp, zp = struct.unpack_from(
            "<6i", buf, start)
        if not (0 < xsiz <= 256 and 0 < ysiz <= 256 and 0 < zsiz <= 256):
            raise KvxError(f"implausible dimensions {xsiz}x{ysiz}x{zsiz} "
                           f"at offset {start}")

        tbl = start + HEADER_BYTES         # offsets are relative to here
        xoff = struct.unpack_from("<%di" % (xsiz + 1), buf, tbl)
        xytbl = tbl + (xsiz + 1) * 4
        xyoff = struct.unpack_from("<%dH" % (xsiz * (ysiz + 1)), buf, xytbl)

        tables = (xsiz + 1) * 4 + xsiz * (ysiz + 1) * 2
        if xoff[0] != tables:
            raise KvxError(f"xoffset[0]={xoff[0]} but the tables occupy "
                           f"{tables} bytes - offsets are not table-relative")
        if HEADER_BYTES + xoff[-1] != length:
            raise KvxError(f"xoffset[-1]={xoff[-1]} implies a mip of "
                           f"{HEADER_BYTES + xoff[-1]} bytes, header says "
                           f"{length}")

        columns = []
        for x in range(xsiz):
            row = []
            for y in range(ysiz):
                lo = tbl + xoff[x] + xyoff[x * (ysiz + 1) + y]
                hi = tbl + xoff[x] + xyoff[x * (ysiz + 1) + y + 1]
                if hi < lo or hi > tbl + xoff[-1]:
                    raise KvxError(f"column ({x},{y}) spans [{lo},{hi}) "
                                   f"which escapes the mip")
                row.append(cls._parse_column(buf, lo, hi, zsiz, x, y))
            columns.append(row)
        return cls(xsiz, ysiz, zsiz, (xp, yp, zp), columns)

    @staticmethod
    def _parse_column(buf, lo, hi, zsiz, x, y):
        slabs = []
        p = lo
        while p < hi:
            if p + 3 > hi:
                raise KvxError(f"column ({x},{y}) ends mid-slab-header")
            ztop, zleng, cull = buf[p], buf[p + 1], buf[p + 2]
            p += 3
            if p + zleng > hi:
                raise KvxError(f"column ({x},{y}) slab at z={ztop} claims "
                               f"{zleng} voxels but only {hi - p} remain")
            if ztop + zleng > zsiz:
                raise KvxError(f"column ({x},{y}) slab spans z "
                               f"{ztop}..{ztop + zleng} beyond zsiz={zsiz}")
            slabs.append(Slab(ztop, cull, buf[p:p + zleng]))
            p += zleng
        return slabs

    # -- serialising -----------------------------------------------------

    def to_bytes(self):
        """Rebuild the tables from `columns` and emit the mip payload."""
        tables = (self.xsiz + 1) * 4 + self.xsiz * (self.ysiz + 1) * 2
        xoff = []
        xyoff = []
        data = bytearray()
        cursor = tables
        for x in range(self.xsiz):
            xoff.append(cursor)
            here = 0
            for y in range(self.ysiz):
                xyoff.append(here)
                for s in self.columns[x][y]:
                    data += bytes((s.ztop, s.zleng, s.cull)) + s.colours
                    here += 3 + s.zleng
            xyoff.append(here)          # sentinel closing the last column
            cursor += here
        xoff.append(cursor)

        out = bytearray(struct.pack("<6i", self.xsiz, self.ysiz, self.zsiz,
                                    *self.pivot))
        out += struct.pack("<%di" % len(xoff), *xoff)
        out += struct.pack("<%dH" % len(xyoff), *xyoff)
        out += data
        return bytes(out)

    # -- construction from a grid ----------------------------------------

    @classmethod
    def from_grid(cls, grid, xsiz, ysiz, zsiz, pivot=None, empty=255):
        """Build a mip from a dense grid.

        `grid` is indexed grid[x][y][z] and yields a palette index, or
        `empty` for air. Only voxels with at least one exposed face are
        kept - interior voxels cost bytes and are never drawn.
        """
        def solid(x, y, z):
            if not (0 <= x < xsiz and 0 <= y < ysiz and 0 <= z < zsiz):
                return False
            return grid[x][y][z] != empty

        if pivot is None:
            # Centre horizontally, base at the model's feet: this matches
            # how Cheello's models are pivoted and puts the sprite's
            # ground line where the engine expects it.
            pivot = (int(xsiz * 128), int(ysiz * 128), int(zsiz * 256))

        columns = []
        for x in range(xsiz):
            row = []
            for y in range(ysiz):
                slabs = []
                run_top = None
                run_cols = []
                run_cull = 0
                for z in range(zsiz):
                    if not solid(x, y, z):
                        if run_top is not None:
                            slabs.append(Slab(run_top, run_cull, run_cols))
                            run_top, run_cols, run_cull = None, [], 0
                        continue
                    cull = 0
                    if not solid(x - 1, y, z):
                        cull |= FACE_LEFT
                    if not solid(x + 1, y, z):
                        cull |= FACE_RIGHT
                    if not solid(x, y - 1, z):
                        cull |= FACE_FRONT
                    if not solid(x, y + 1, z):
                        cull |= FACE_BACK
                    if not solid(x, y, z - 1):
                        cull |= FACE_TOP
                    if not solid(x, y, z + 1):
                        cull |= FACE_BOTTOM
                    if cull == 0:
                        # fully enclosed: invisible, so break the run
                        if run_top is not None:
                            slabs.append(Slab(run_top, run_cull, run_cols))
                            run_top, run_cols, run_cull = None, [], 0
                        continue
                    if run_top is None:
                        run_top = z
                    run_cols.append(grid[x][y][z])
                    run_cull |= cull
                if run_top is not None:
                    slabs.append(Slab(run_top, run_cull, run_cols))
                row.append(slabs)
            columns.append(row)
        return cls(xsiz, ysiz, zsiz, pivot, columns)


class Kvx:
    """A complete .kvx file: one or more mip levels plus a palette."""

    def __init__(self, mips, palette):
        self.mips = mips
        self.palette = bytes(palette)
        if len(self.palette) != PALETTE_BYTES:
            raise KvxError(f"palette is {len(self.palette)} bytes, "
                           f"expected {PALETTE_BYTES}")

    @classmethod
    def parse(cls, buf):
        buf = bytes(buf)
        if len(buf) < PALETTE_BYTES + 4 + HEADER_BYTES:
            raise KvxError(f"file is {len(buf)} bytes, too short to be KVX")
        body_end = len(buf) - PALETTE_BYTES
        mips = []
        off = 0
        while off + 4 <= body_end:
            (n,) = struct.unpack_from("<i", buf, off)
            if n <= 0 or off + 4 + n > body_end:
                break
            mips.append(KvxMip.parse(buf, off + 4, n))
            off += 4 + n
        if not mips:
            raise KvxError("no readable mip levels")
        if off != body_end:
            raise KvxError(f"{body_end - off} trailing bytes before the "
                           f"palette - mip chain is inconsistent")
        return cls(mips, buf[body_end:])

    def to_bytes(self):
        out = bytearray()
        for m in self.mips:
            payload = m.to_bytes()
            out += struct.pack("<i", len(payload)) + payload
        out += self.palette
        return bytes(out)

    @classmethod
    def from_grid(cls, grid, xsiz, ysiz, zsiz, palette, pivot=None,
                  empty=255):
        """Single-mip KVX from a dense grid. UZDoom renders mip 0; the
        extra levels in Cheello's files are optional distance LODs."""
        return cls([KvxMip.from_grid(grid, xsiz, ysiz, zsiz, pivot, empty)],
                   palette)


# ---------------------------------------------------------------------------
# Verification: round-trip real files and require byte equality.
#
# A codec validated only against its own output proves nothing - it just
# confirms it is self-consistent. Cheello's 530 shipped models are an
# INDEPENDENT source of truth: they were produced by different tools and
# are known to render correctly in the engine we target.
# ---------------------------------------------------------------------------

def _sources(target):
    p = Path(target)
    if p.is_dir():
        for f in sorted(p.rglob("*.kvx")):
            yield str(f), f.read_bytes()
    elif p.suffix.lower() in (".pk3", ".zip", ".pk7"):
        z = zipfile.ZipFile(p)
        for n in sorted(z.namelist()):
            if n.lower().endswith(".kvx"):
                yield n, z.read(n)
    elif p.suffix.lower() == ".kvx":
        yield str(p), p.read_bytes()
    else:
        raise SystemExit(f"don't know how to read voxels from {target}")


def verify(target, verbose=False):
    total = ok = 0
    failures = []
    stats = {"mips": 0, "slabs": 0, "voxels": 0}
    for name, raw in _sources(target):
        total += 1
        try:
            k = Kvx.parse(raw)
            out = k.to_bytes()
        except KvxError as e:
            failures.append(f"{name}: parse failed: {e}")
            continue
        except Exception as e:                      # noqa: BLE001
            failures.append(f"{name}: {type(e).__name__}: {e}")
            continue
        if out != raw:
            where = next((i for i, (a, b) in enumerate(zip(out, raw))
                          if a != b), min(len(out), len(raw)))
            failures.append(f"{name}: re-encoded {len(out)} bytes vs "
                            f"{len(raw)} original, first difference at "
                            f"byte {where}")
            continue
        ok += 1
        stats["mips"] += len(k.mips)
        stats["slabs"] += k.mips[0].slab_count()
        stats["voxels"] += k.mips[0].voxel_count()
        if verbose:
            m = k.mips[0]
            print(f"  {name}: {m.xsiz}x{m.ysiz}x{m.zsiz} "
                  f"pivot {m.pivot_f} {m.slab_count()} slabs")

    print(f"round-tripped {ok}/{total} files byte-for-byte")
    if ok:
        print(f"  {stats['mips']} mip levels, {stats['slabs']} slabs, "
              f"{stats['voxels']} surface voxels in mip 0")
    for f in failures[:20]:
        print("  FAIL", f)
    if len(failures) > 20:
        print(f"  ... and {len(failures) - 20} more")
    return not failures


def make_cube(path, size=16):
    """A solid cube in the Wolf palette - the engine-proof model."""
    grid = [[[0 if (x + y) % 8 else 4 for z in range(size)]
             for y in range(size)] for x in range(size)]
    pal = bytearray(PALETTE_BYTES)
    for i in range(256):                    # a visible ramp; 6-bit VGA
        pal[i * 3:i * 3 + 3] = bytes((i >> 2, (255 - i) >> 2, 32))
    k = Kvx.from_grid(grid, size, size, size, bytes(pal))
    Path(path).write_bytes(k.to_bytes())
    m = k.mips[0]
    print(f"wrote {path}: {size}^3, {m.slab_count()} slabs, "
          f"{m.voxel_count()} surface voxels "
          f"({m.voxel_count() * 100 // size ** 3}% of solid)")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--verify", metavar="PK3|DIR|KVX",
                    help="round-trip every KVX found and require byte "
                         "equality with the original")
    ap.add_argument("--cube", metavar="OUT.KVX",
                    help="write a test cube for the in-engine proof")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    if not (a.verify or a.cube):
        ap.error("nothing to do: pass --verify and/or --cube")
    rc = 0
    if a.verify and not verify(a.verify, a.verbose):
        rc = 1
    if a.cube:
        make_cube(a.cube)
    sys.exit(rc)


if __name__ == "__main__":
    main()
