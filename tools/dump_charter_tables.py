#!/usr/bin/env python3
"""Extract verbatim data tables from WOLFSRC into docs/data/*.json.

Re-runnable stage (house rule: never hand-patch generated artifacts).
Tables: rndtable (ID_US_A.ASM), vgaCeiling (WL_DRAW.C), parTimes (WL_INTER.C),
statinfo blocking table (WL_ACT1.C).
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"
OUT = ROOT / "docs" / "data"


def dump_rndtable():
    text = (SRC / "ID_US_A.ASM").read_text(errors="replace")
    m = re.search(r"rndtable\s+db(.*?)(?:\n\S|\n\s*\n)", text, re.S)
    block = m.group(1)
    # continuation lines start with 'db'
    nums = [int(n) for n in re.findall(r"\b\d+\b", block.replace("db", " "))]
    assert len(nums) == 256, f"rndtable expected 256 entries, got {len(nums)}"
    return nums


def dump_vga_ceiling():
    text = (SRC / "WL_DRAW.C").read_text(errors="replace")
    m = re.search(r"unsigned vgaCeiling\[\]=\s*\{(.*?)\};", text, re.S)
    body = m.group(1)
    wl6_part, _, spear_part = body.partition("#else")
    def vals(s):
        return [int(v, 16) & 0xFF for v in re.findall(r"0x([0-9a-fA-F]+)", s)]
    wl6 = vals(wl6_part)
    spear = vals(spear_part)
    assert len(wl6) == 60, f"WL6 ceilings expected 60, got {len(wl6)}"
    assert len(spear) == 21, f"SOD ceilings expected 21, got {len(spear)}"
    return {"wl6": wl6, "sod": spear, "floor_color": 0x19,
            "note": "ceiling color per level (episode*10+map for WL6); floor fixed 0x19 (VGAClearScreen WL_DRAW.C:1004)"}


def dump_par_times():
    text = (SRC / "WL_INTER.C").read_text(errors="replace")
    m = re.search(r"times parTimes\[\]=\s*\{(.*?)\n\s*\};", text, re.S)
    body = m.group(1)
    wl6_part, _, spear_part = body.partition("#else")
    def vals(s):
        return [
            {"minutes": float(mm), "display": disp}
            for mm, disp in re.findall(r"\{\s*([\d.]+)\s*,\s*\"([^\"]*)\"", s)
        ]
    wl6 = vals(wl6_part)
    sod = vals(spear_part)
    assert len(wl6) == 60, f"WL6 par times expected 60, got {len(wl6)}"
    # SOD table has exactly 20 rows in source (bosses/secrets par 0 = "??:??");
    # 21-floor structure maps onto it via mapon indexing — verify in Phase 1.
    assert len(sod) == 20, f"SOD par times expected 20, got {len(sod)}"
    return {"wl6": wl6, "sod": sod,
            "note": "bonus = max(0, par_seconds - time_seconds) * 500 (WL_INTER.C:624,663)"}


def dump_statinfo():
    text = (SRC / "WL_ACT1.C").read_text(errors="replace")
    m = re.search(r"\}\s*statinfo\[\]\s*=\s*\{(.*?)\n\};", text, re.S)
    body = m.group(1)
    rows = []
    idx = 0
    ifdef_stack = []
    for line in body.splitlines():
        s = line.strip()
        if s.startswith("#ifndef"):
            ifdef_stack.append("ifndef " + s.split()[1])
            continue
        if s.startswith("#ifdef"):
            ifdef_stack.append("ifdef " + s.split()[1])
            continue
        if s.startswith("#else"):
            if ifdef_stack:
                ifdef_stack[-1] = "!" + ifdef_stack[-1]
            continue
        if s.startswith("#endif"):
            if ifdef_stack:
                ifdef_stack.pop()
            continue
        m2 = re.match(r"\{SPR_STAT_(\d+)(?:,\s*([A-Za-z_0-9]+))?\}\s*,?\s*(?://\s*(.*))?", s)
        if not m2:
            continue
        sprite, attr, comment = m2.groups()
        rows.append({
            "index": idx,
            "sprite": int(sprite),
            "class": attr or "dressing",
            "comment": (comment or "").strip(),
            "cond": " & ".join(ifdef_stack) if ifdef_stack else None,
        })
        idx += 1
    assert len(rows) >= 48, f"statinfo expected >=48 rows, got {len(rows)}"
    return {"rows": rows,
            "note": "class: dressing=walk-through, block=solid (actorat=1; blocks movement not sight/shots), bo_*=pickup. Map object code = 23+index (MAP-002). Conditional rows share an index across builds."}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tables = {
        "rndtable.json": {"values": dump_rndtable(),
                          "note": "US_RndT table, ID_US_A.ASM:19; index+1 per call, wraps at 256 (RNG-001)"},
        "ceiling_colors.json": dump_vga_ceiling(),
        "par_times.json": dump_par_times(),
        "statinfo.json": dump_statinfo(),
    }
    for name, data in tables.items():
        (OUT / name).write_text(json.dumps(data, indent=1))
        print(f"wrote docs/data/{name}")


if __name__ == "__main__":
    main()
