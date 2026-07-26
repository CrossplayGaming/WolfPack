# Fidelity Charter — Wolf3D → UZDoom

The conversion contract. Every gameplay constant that enters the sim must appear here with
(value, source file:line in WOLFSRC, converted value, assertion ID). The harness asserts every
row. Companion docs: `WOLF_UZDOOM_HANDOFF.md` (project plan), `WOLF_FIDELITY_CHECKLIST.md`
(curated highlights), `COVERAGE_LEDGER.md` (Phase 0.5, exhaustiveness bookkeeping — to be built).

Source paths below are relative to `reference/wolfsrc/WOLFSRC/` (id Software GPL release,
cloned from github.com/id-Software/wolf3d, extracted tree).

## Tic-rate mapping (proposed policy — confirm at Phase 0 exit)

Wolf3D counts `tics` in 1/70 s units (VGA VBL). Doom/UZDoom runs 35 Hz. The ratio is exactly
2:1, so the policy is **zero-rounding**: the sim keeps all timing state in original Wolf tics
(integers) and advances **2 Wolf tics per Doom tic**. No constant is ever divided, scaled, or
rounded; odd tic counts (reaction delays, attack frames) are preserved exactly. Presentation
interpolates freely.

- Assertion `TIC-001`: sim advances exactly 2 Wolf tics per engine tic.

## Constants inventory — RESOLVED (batch 1, 2026-07-26)

### Map object codes (plane 1 "info plane") — `WL_GAME.C` ScanInfoPlane (l. 221+)

| ID | Item | Value | Source |
|---|---|---|---|
| MAP-001 | Player start N/E/S/W | 19–22 | WL_GAME.C:237-242 |
| MAP-002 | Static objects | 23–74 (`SpawnStatic(tile-23)`) | WL_GAME.C:244-299 |
| MAP-003 | Pushwall | 98 (`secrettotal++`) | WL_GAME.C:304-307 |
| MAP-004 | Dead guard (decor) | 124 | WL_GAME.C:352-354 |
| MAP-005 | Difficulty tiers | base = easy+, **+36** = medium+, **+72** = hard+ | WL_GAME.C:311+ pattern |
| MAP-006 | Guard stand / patrol | 108–111 / 112–115 (+tiers) | WL_GAME.C:311-350 |
| MAP-007 | Officer stand / patrol | 116–119 / 120–123 (+tiers) | WL_GAME.C:356-400 |
| MAP-008 | SS stand / patrol | 126–129 / 130–133 (+tiers) | WL_GAME.C:402-446 |
| MAP-009 | Dog (patrol-only spawn) | 134–137 base (+tiers) | WL_GAME.C:448+ |
| MAP-010 | Direction encoding | tile−base: 0=N,1=E,2=S,3=W | SpawnStand/SpawnPatrol calls |

Remaining spawn codes (mutants, bosses, ghosts, treasure-as-plane1, turn-tiles 90–97, secret
elevator 107 handling, SoD extras) → batch 2, same file.

### Map tile codes (plane 0) — `WL_DEF.H`

| ID | Item | Value | Source |
|---|---|---|---|
| TILE-001 | AREATILE (first area floor code) | 107 | WL_DEF.H:61 |
| TILE-002 | NUMAREAS | 37 | WL_DEF.H:62 |
| TILE-003 | AMBUSHTILE | 106 | WL_DEF.H:64 |
| TILE-004 | EXITTILE | 99 | WL_DEF.H:60 |
| TILE-005 | ALTELEVATORTILE | 107 | WL_DEF.H:65 |
| TILE-006 | MAXDOORS | 64 | WL_DEF.H:51 |

Ambush semantics: after ScanInfoPlane, AMBUSHTILE cells are cleared and the floor code is
patched from a neighboring ≥AREATILE cell (WL_GAME.C:729-751). Actors spawned on an ambush
tile get `FL_AMBUSH` (=64, WL_DEF.H:151; set in SpawnStand/SpawnPatrol, e.g. WL_ACT2.C:884-901).
In `SightPlayer`, FL_AMBUSH actors **skip the `madenoise` check entirely** — they activate on
`CheckSight` only, and the flag clears on first sighting (WL_STATE.C:1424-1429). They still
require `areabyplayer[areanumber]` (WL_STATE.C:1421).

### Enemy reaction times — `WL_STATE.C` SightPlayer (l. 1436-1467)

Reaction delay in Wolf tics, set when first stimulus lands; counts down via `temp2 -= tics`.
`US_RndT()` returns 0–255 (table-driven PRNG — port the table for determinism).

| ID | Class | Delay (tics) |
|---|---|---|
| REACT-001 | Guard | 1 + RndT/4 |
| REACT-002 | Officer | 2 (fixed) |
| REACT-003 | Mutant | 1 + RndT/6 |
| REACT-004 | SS | 1 + RndT/6 |
| REACT-005 | Dog | 1 + RndT/8 |
| REACT-006 | All bosses/specials | 1 (fixed) |

### Doors — `WL_ACT1.C`

| ID | Item | Value | Source |
|---|---|---|---|
| DOOR-001 | Auto-close delay | OPENTICS = 300 tics (≈4.29 s) | WL_ACT1.C:270,540 |
| DOOR-002 | Slide rate | `position += tics<<10` → full travel 0→0xFFFF in 64 tics (≈0.91 s) | WL_ACT1.C:593 |
| DOOR-003 | DOORWIDTH (blocking threshold) | 0x7800 | WL_ACT1.C:269 |

Blocked-reopen / close-interrupt semantics → batch 2 (read CloseDoor/DoorOpening fully).

### Pushwalls — `WL_ACT1.C` PushWall/MovePWalls (l. 719-897)

| ID | Item | Value |
|---|---|---|
| PWALL-001 | Travel distance | 2 tiles: state += tics, 128 units = 1 tile, stops when state > 256 (l. 816-840) |
| PWALL-002 | Blocked-by-actor | at each tile boundary, if `actorat` ahead is occupied → stop immediately (l. 845-893) |
| PWALL-003 | Concurrency | only one pushwall may move at a time (`if (pwallstate) return`, l. 736) |
| PWALL-004 | Render position | pwallpos = (state/2) & 63 — 64 sub-tile positions (l. 897) |
| PWALL-005 | Push start | tile info removed from plane 1; tilemap flagged 0xC0 (l. 788-794) |

### Player combat — `WL_AGENT.C`

Hitscan (GunAttack, l. 1168-1242): target = closest actor with FL_SHOOTABLE|FL_VISABLE within
`shootdelta` of screen center, passing CheckLine. Distance = Chebyshev tile distance
max(|dx|,|dy|).

| ID | Item | Value |
|---|---|---|
| PCOMBAT-001 | dist < 2 | damage = RndT/4 (0–63) |
| PCOMBAT-002 | dist < 4 | damage = RndT/6 (0–42) |
| PCOMBAT-003 | dist ≥ 4 | miss if RndT/12 < dist; else damage = RndT/6 |

Weapon cadence (attackinfo table, WL_AGENT.C:64-73; engine at l. 1320-1376): all four weapons
run 4 frames × **6 tics**. Attack codes: 0=none, 1=fire one shot, 2=knife, 3=rewind 2 frames if
button held (machine gun), 4=fire AND rewind if held (chaingun), −1=end/lower.

| ID | Item | Value |
|---|---|---|
| WEAP-001 | Knife | semi-auto, 1 attack per 24-tic cycle (frame 2, attack=2) |
| WEAP-002 | Pistol | semi-auto, 1 shot per cycle (frame 1, attack=1) |
| WEAP-003 | Machine gun | held: 1 shot per 12 tics (fire frame + rewind frame) |
| WEAP-004 | Chaingun | held: 2 shots per 12 tics (attack=1 frame then attack=4 frame) |
| WEAP-005 | Auto-switch | ammo==0 at cycle end → knife; also restores chosenweapon (l. 1329-1343) |

### Player damage / difficulty — `WL_AGENT.C` TakeDamage (l. 386+)

| ID | Item | Value |
|---|---|---|
| DIFF-001 | Baby-skill damage scale | `points >>= 2` (quarter damage) — WL_AGENT.C:392-393 |
| DIFF-002 | Enemy starting HP | `starthitpoints[difficulty][class]` table (WL_ACT2.C:904) → dump in batch 2 |

### Enemy death: points + drops — `WL_STATE.C` KillActor (l. 810+)

Drops use PlaceItemType at death tile, spilling to a free neighbor in the 3×3 if occupied
(l. 783-803).

| ID | Class | Points | Drop |
|---|---|---|---|
| KILL-001 | Guard | 100 | bo_clip2 |
| KILL-002 | Officer | 400 | bo_clip2 |
| KILL-003 | SS | 500 | machine gun if bestweapon < machinegun, else bo_clip2 |
| KILL-004 | Dog | 200 | none |
| KILL-005 | Mutant | 700 | bo_clip2 |

### Pickups — `WL_AGENT.C` GetBonus (l. 660+)

Denial at caps: health items refused at health==100; ammo refused at ammo==99 (item remains).

| ID | Item | Effect |
|---|---|---|
| PICK-001 | Clip (placed) | +8 ammo |
| PICK-002 | Clip (enemy-dropped, bo_clip2) | +4 ammo |
| PICK-003 | Ammo box (bo_25clip, SoD) | +25 ammo |
| PICK-004 | First aid kit | +25 health |
| PICK-005 | Food | +10 health |
| PICK-006 | Dog food (bo_alpo) | +4 health |
| PICK-007 | 1-Up (bo_fullheal) | heal to 99(+), +25 ammo, +1 life, counts as treasure |

### Scoring / progression

| ID | Item | Value | Source |
|---|---|---|---|
| SCORE-001 | Extra life every | 40,000 pts (EXTRAPOINTS) | WL_DEF.H:72, WL_AGENT.C:526-528 |
| SCORE-002 | Par bonus | 500 pts/second under par (PAR_AMOUNT) | WL_INTER.C:432,663 |
| SCORE-003 | 100% category bonus | 10,000 pts each for kills/secrets/treasure (PERCENT100AMT) | WL_INTER.C:433,714,759 |
| SCORE-004 | Health/ammo caps | 100 / 99 | WL_AGENT.C:672,709 |

## Open [VERIFY] items — batch 2 queue

- Enemy→player hit chance roll (distance, player-moving modifier) — WL_ACT2.C T_Shoot.
- starthitpoints table dump (all classes × difficulties) — WL_ACT2.C.
- Knife attack range/damage — WL_AGENT.C KnifeAttack.
- Projectile speeds/damage: Schabbs syringe, fake-Hitler fireball, boss rockets — WL_ACT2.C.
- Remaining spawn codes: mutants, bosses, ghosts, turn-tiles (90–97?), en_* full map.
- Door blocked-reopen and close-on-obstruction semantics — WL_ACT1.C CloseDoor/DoorOpening.
- Death/restart semantics (lives, score reset, loadout) — WL_GAME.C Died.
- Fizzle-fade LFSR constants — WL_DRAW.C or ID_VH/ID_VL FizzleFade.
- Screen flash (damage/bonus) intensities + durations — WL_PLAY.C palette shifts.
- Keyboard turn acceleration ramp + run speeds — WL_AGENT.C ControlMovement / WL_PLAY.C.
- Decoration blocking table — WL_ACT1.C statinfo.
- US_RndT table itself (ID_US_A.ASM / ID_US.H) — port verbatim for determinism.
- Area-connect / madenoise propagation details — WL_STATE.C/WL_PLAY.C.
- End-of-floor time accounting (timeleft units) — WL_INTER.C LevelCompleted.
- SoD deltas pass.

## Decision log (Doom-architecture approximations)

Format: ID, what Wolf does, what we do instead, why, gameplay-visibility argument.
Target: zero gameplay-visible entries.

*(empty)*
