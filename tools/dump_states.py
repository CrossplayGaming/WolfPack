#!/usr/bin/env python3
"""Extract every statetype definition from WOLFSRC into docs/data/state_tables.json.

Each entry: {name, rotate, sprite, tics, think, action, next, file, line, cond}.
This is the ledger's state-table diff source: as ZScript actors are written in
Phase 2, their states diff against this file mechanically (per-enemy
completeness proof). Re-runnable stage; never hand-edit the output.

statetype layout (WL_DEF.H): boolean rotate; int shapenum; int tictime;
                             think_t think; think_t action; statetype *next;
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "wolfsrc" / "WOLFSRC"
OUT = ROOT / "docs" / "data"

STATE_RE = re.compile(
    r"statetype\s+(s_[A-Za-z0-9_]+)\s*=\s*\{\s*"
    r"([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*&?([A-Za-z0-9_]+)\s*\}"
)
COND_RE = re.compile(r"#(ifndef|ifdef|else|endif)\s*([A-Za-z0-9_]*)")


def clean(s: str) -> str:
    return s.strip().replace("\t", " ")


def main():
    states = []
    for path in sorted(SRC.glob("*.C")):
        lines = path.read_text(errors="replace").splitlines()
        stack = []
        for i, line in enumerate(lines, 1):
            mc = COND_RE.match(line.strip())
            if mc:
                kind, sym = mc.groups()
                if kind == "ifndef":
                    stack.append(f"!{sym}")
                elif kind == "ifdef":
                    stack.append(sym)
                elif kind == "else" and stack:
                    stack[-1] = stack[-1][1:] if stack[-1].startswith("!") else f"!{stack[-1]}"
                elif kind == "endif" and stack:
                    stack.pop()
                continue
            m = STATE_RE.search(line)
            if m:
                name, rotate, sprite, tics, think, action, nxt = (clean(g) for g in m.groups())
                states.append({
                    "name": name,
                    "rotate": rotate,      # true/false/1/2 (2 = dir-rotated pain hack)
                    "sprite": sprite,
                    "tics": tics,
                    "think": None if think == "NULL" else think,
                    "action": None if action == "NULL" else action,
                    "next": None if nxt == "NULL" else nxt,
                    "file": path.name,
                    "line": i,
                    "cond": " & ".join(stack) if stack else None,
                })
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "state_tables.json").write_text(json.dumps({
        "note": "statetype fields: rotate, sprite, tics(Wolf 1/70s), think(per-tic), "
                "action(on state entry via NewState/ticcount expiry), next. "
                "cond uses build symbols (SPEAR etc.).",
        "count": len(states),
        "states": states,
    }, indent=1))
    print(f"wrote docs/data/state_tables.json with {len(states)} states")
    # sanity: known anchors must be present
    names = {s["name"] for s in states}
    for anchor in ("s_grdchase1", "s_rocket", "s_hitlerchase1", "s_player", "s_boom1"):
        assert anchor in names, f"missing anchor state {anchor}"
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
