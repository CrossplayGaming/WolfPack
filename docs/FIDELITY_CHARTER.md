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

## Constants inventory — RESOLVED (batch 2, 2026-07-26)

### Complete spawn-code map (plane 1) — `WL_GAME.C` ScanInfoPlane (continued)

| ID | Item | Value | Notes |
|---|---|---|---|
| MAP-011 | Dog stand / patrol | 134–137 / 138–141 (+36/+72 tiers) | WL_GAME.C:448-497 |
| MAP-012 | Mutant stand / patrol | 216–219 / 220–223, tiers **+18** (234/252, 238/256) | WL_GAME.C:547-585 — mutants use +18, NOT +36 |
| MAP-013 | Bosses (WL6) | 214 Hans, 197 Gretel, 215 Gift, 179 Fat, 196 Schabbs, 160 Fake Hitler, 178 Hitler | WL_GAME.C:500-524 — single code, all difficulties |
| MAP-014 | Ghosts | 224 Blinky, 225 Clyde, 226 Pinky, 227 Inky | WL_GAME.C:589-600 |
| MAP-015 | SoD specials | 106 Spectre, 107 Angel, 125 Trans, 142 Uber, 143 Will, 161 Death | WL_GAME.C:526-543 (SPEAR) |
| MAP-016 | Patrol turn-tiles | ICONARROWS = 90; codes 90–97 = 8 directions (`spot = code-90; if (spot<8) dir = spot`) | WL_DEF.H:58, WL_ACT2.C SelectPathDir:3340-3356 |
| MAP-017 | **Victory trigger: plane-1 code 99 (EXITTILE)** — player walking onto it fires VictoryTile() → BJ victory sequence (checked every Thrust) | WL_AGENT.C:961-962 — found by extractor loud-fail, not in checklist |

Turn-tiles are consulted only when a pathing actor reaches tile center with `dir` set; then
`distance = TILEGLOBAL`, and if `TryWalk` fails → `nodir` (wait). Patrolling enemies stop at
closed doors and open them via `distance = -(doornum+1)` encoding (T_Path, WL_ACT2.C:3387-3396).

### Enemy starting HP — `WL_ACT2.C` starthitpoints (l. 42-155)

| ID=HP-xxx | Baby | Easy | Medium | Hard |
|---|---|---|---|---|
| Guard | 25 | 25 | 25 | 25 |
| Officer | 50 | 50 | 50 | 50 |
| SS | 100 | 100 | 100 | 100 |
| Dog | 1 | 1 | 1 | 1 |
| Hans | 850 | 950 | 1050 | 1200 |
| Schabbs | 850 | 950 | 1550 | 2400 |
| Fake Hitler | 200 | 300 | 400 | 500 |
| Mecha Hitler | 800 | 950 | 1050 | 1200 |
| Mutant | 45 | 55 | 55 | 65 |
| Ghosts (each) | 25 | 25 | 25 | 25 |
| Gretel / Gift / Fat | 850 | 950 | 1050 | 1200 |
| Spectre | 5 | 10 | 15 | 25 |
| Angel | 1450 | 1550 | 1650 | 2000 |
| Trans | 850 | 950 | 1050 | 1200 |
| Uber | 1050 | 1150 | 1250 | 1400 |
| Will | 950 | 1050 | 1150 | 1300 |
| Death Knight | 1250 | 1350 | 1450 | 1600 |

### Enemy → player combat — `WL_ACT2.C` T_Shoot (l. 3444-3518), T_Bite (l. 3530-3560)

| ID | Item | Value |
|---|---|---|
| ECOMBAT-001 | Base gate | no shot unless `areabyplayer` and CheckLine passes |
| ECOMBAT-002 | Distance | Chebyshev tiles; SS and Hans: `dist = dist*2/3` (better shots) |
| ECOMBAT-003 | Hit chance, player running (thrustspeed ≥ RUNSPEED 6000) | visible: 160−dist·16; not visible: 160−dist·8 |
| ECOMBAT-004 | Hit chance, player slow/still | visible: 256−dist·16; not visible: 256−dist·8 |
| ECOMBAT-005 | Hit if | RndT() < hitchance |
| ECOMBAT-006 | Damage | dist<2: RndT>>2; dist<4: RndT>>3; else RndT>>4 |
| ECOMBAT-007 | Dog bite | adjacency: per-axis |Δ|−TILEGLOBAL ≤ MINACTORDIST (0x10000); hit if RndT<180; damage RndT>>4 |

### Sneak attack + pain states — `WL_STATE.C` DamageActor (l. 964-1010)

| ID | Item | Value |
|---|---|---|
| ECOMBAT-008 | **Unalerted actors take DOUBLE damage** (`damage <<= 1` if !FL_ATTACKMODE) | l. 969-972 — not in the checklist; major stealth mechanic |
| ECOMBAT-009 | Pain state chosen by HP parity (hitpoints&1 → variant 1 else 2) for guard/officer/mutant/SS | l. 983-1010 |
| ECOMBAT-010 | Dogs (1 HP) and all bosses: no pain entries in the switch → never flinch | by absence, same switch |

### Chase-mode speeds — `WL_STATE.C` FirstSighting (l. 1253-1400), spawn speeds `WL_ACT2.C`

Patrol/stand base speed SPDPATROL = 512, dogs SPDDOG = 1500 (WL_ACT2.C:1028-1029).

| ID | Class | Chase speed |
|---|---|---|
| SPEED-001 | Guard | ×3 (1536) |
| SPEED-002 | Officer | ×5 (2560) |
| SPEED-003 | Mutant | ×3 |
| SPEED-004 | SS | ×4 (2048) |
| SPEED-005 | Dog | ×2 (3000) |
| SPEED-006 | Hans | = SPDPATROL×3 |
| SPEED-007 | Gretel/Gift/Fat/Schabbs/Fake Hitler/Mecha | ×3 |
| SPEED-008 | Real Hitler | ×5 |
| SPEED-009 | Ghosts | ×2 |
| SPEED-010 | Spectre 800; Angel/Trans 1536 (absolute) | SoD |

### Projectiles — `WL_ACT2.C`

| ID | Item | Value |
|---|---|---|
| PROJ-001 | Rocket (Gift/Fat/SoD hrocket) | speed 0x2000, damage RndT>>3 + 30 |
| PROJ-002 | Schabbs needle | speed 0x2000, damage RndT>>3 + 20 |
| PROJ-003 | Fake Hitler fire | speed 0x1200, damage RndT>>3 |
| PROJ-004 | Angel spark (SoD) | speed 0x2000, damage RndT>>3 + 30 |
| PROJ-005 | Player hit radius | PROJECTILESIZE = 0xC000 per axis (WL_ACT2.C:14,344) |
| PROJ-006 | Movement | per-tic delta clamped to 0x10000/axis; wall hit → rocket booms, others vanish (T_Projectile l. 302-342) |

### Player knife — `WL_AGENT.C` KnifeAttack (l. 1133-1164)

| ID | Item | Value |
|---|---|---|
| KNIFE-001 | Target | same screen-center pick as guns; hit only if view depth ≤ 0x18000 (1.5 tiles) |
| KNIFE-002 | Damage | RndT>>4 (0–15) |

### Player movement — `WL_AGENT.C` / `WL_PLAY.C`

| ID | Item | Value |
|---|---|---|
| MOVE-001 | Keyboard input | BASEMOVE 35, RUNMOVE 70 per tic (WL_PLAY.C:246-249) |
| MOVE-002 | Forward/strafe scale | MOVESCALE 150; backward BACKMOVESCALE 100 — **backpedal is slower** (WL_AGENT.C:18-19,207-214) |
| MOVE-003 | Turn rate | controlx/ANGLESCALE(20) angle-units — walk 1.75°/tic, run 3.5°/tic (WL_AGENT.C:20,191-192) |
| MOVE-004 | **No keyboard turn-acceleration ramp exists** (BASETURN/RUNTURN defined but the keyboard path uses BASEMOVE/RUNMOVE flat) | corrects checklist §3 — verify DOSBox feel anyway |
| MOVE-005 | RUNSPEED threshold (enemy accuracy) | 6000 (WL_DEF.H:75) |
| MOVE-006 | PLAYERSIZE/collision MINDIST etc. | batch 3 (ClipMove/TryMove) |

### Doors: operate/close rules — `WL_ACT1.C` (l. 417-540)

| ID | Item | Value |
|---|---|---|
| DOOR-004 | Locked doors | lock 1–4 vs `gamestate.keys` bitmask; fail → NOWAYSND (OperateDoor l. 498-510) |
| DOOR-005 | Use while closing → reopens; while opening → closes | OperateDoor switch l. 512-522 |
| DOOR-006 | Won't close on: actor on door tile, player on tile, or player/adjacent actor within MINDIST of the door plane | CloseDoor l. 428-448 |
| DOOR-007 | Sound propagation: open door joins its two areas (areaconnect++ / ConnectAreas flood); alerting flood is `RecursiveConnect` from player area | WL_ACT1.C:293-320 |

`madenoise` is reset every frame (WL_PLAY.C:1404) and set by player gunfire (WL_AGENT.C:1188)
and by DamageActor (WL_STATE.C:966). Enemies test `madenoise && areabyplayer[their area]`.

### Screen flashes — `WL_PLAY.C` (l. 1054-1215)

| ID | Item | Value |
|---|---|---|
| FLASH-001 | Bonus flash | bonuscount = NUMWHITESHIFTS(3)×WHITETICS(6) = 18 tics; index = count/6+1 cap 3; whiteshift ramp delta·i/WHITESTEPS(20) toward 64 |
| FLASH-002 | Damage flash | damagecount += damage taken (intensity scales with damage!); index = count/10+1 cap NUMREDSHIFTS(6); ramp delta·i/REDSTEPS(8); count −= tics |
| FLASH-003 | Priority | red overrides white (UpdatePaletteShifts l. 1201-1211) |

### Fizzle-fade — `ID_VH.C` FizzleFade (l. 471-540)

| ID | Item | Value |
|---|---|---|
| FIZZ-001 | Generator | 17-bit Fibonacci LFSR, seed rndval=1; per step: 32-bit pair shifted right 1; on carry XOR high word 0x0001, low word 0x2000 |
| FIZZ-002 | Pixel mapping | y = (low 8 bits)−1; x = next 9 bits; out-of-bounds skipped |
| FIZZ-003 | Rate | 64000/frames pixels per frame; player-death call uses frames=70 (WL_GAME.C:1197) |
| FIZZ-004 | Termination | when rndval returns to 1 (full period) |

### Death / lives — `WL_GAME.C` Died (l. 1114-1225), GameLoop

| ID | Item | Value |
|---|---|---|
| DEATH-001 | Death cam rotate to killer | DEATHROTATE = 2 angle-units/tic (l. 1112, 1155-1188) |
| DEATH-002 | Sequence | weapon removed → rotate → red fade → FizzleFade(70) to solid red (color 4) |
| DEATH-003 | Restart loadout | health 100, pistol only (weapon=bestweapon=chosenweapon), ammo = STARTAMMO 8, keys 0 (l. 1206-1215; WL_DEF.H:140) |
| DEATH-004 | **Score restored to level-entry value** (`score = oldscore`; oldscore saved on level completion) | WL_GAME.C:1256,1304 |
| DEATH-005 | Lives decrement unless tedlevel | l. 1203-1204 |

### Tally time — `WL_INTER.C`

| ID | Item | Value |
|---|---|---|
| TALLY-001 | Level time = TimeCount/70 seconds, capped display 99:59; par stored as minutes → `time*4200/70` seconds; timeleft in **seconds** | WL_INTER.C:618-624 |
| TALLY-002 | Par bonus 500/s (SCORE-002); count-up beeps every 50 | WL_INTER.C:663-672 |

### RNG — `ID_US_A.ASM`

| ID | Item | Value |
|---|---|---|
| RNG-001 | US_RndT = 256-entry byte table (ID_US_A.ASM:19-37), index advances by 1 per call, seeded from BIOS timer (US_InitRndT) | port the table verbatim; sim determinism depends on it |

### Decoration blocking table — `WL_ACT1.C` statinfo (l. 22-135)

Full table (statics 0–47+): entries are `{sprite}` = walk-through, `{sprite,block}` = solid,
`{sprite,bo_*}` = pickup. Blocking set (WL6): green barrel, table/chairs, floor lamp, hanged
man, red pillar, tree, sink, potted plant, urn, bare table, suit of armor, hanging cage,
skeleton in cage, barrel, well (both), flag, plus SoD gib variants. Non-blocking: puddle,
chandelier, skeleton flat, ceiling light, kitchen stuff, skeleton relax, junk/stuff, pots.
Converter ports this table mechanically from the source rows (assertion per row: BLOCK-000…047).
Blocking statics write `actorat = 1` (SpawnStatic l. 146-152) — they block movement but not
sight/shots.

## Constants inventory — RESOLVED (batch 3, 2026-07-26)

### Chase pathing — `WL_STATE.C` TryWalk (l. 181-333), SelectChaseDir (l. 475-570), SelectDodgeDir (l. 359-443); `WL_ACT2.C` T_Chase (l. 3069-3195)

| ID | Item | Value |
|---|---|---|
| CHASE-001 | actorat encoding | <128 wall, 128–255 door (`doornum = value&63`), ≥256 actor ptr (blocks if FL_SHOOTABLE) |
| CHASE-002 | Cardinal moves may pass doors (CHECKSIDE); diagonals never (CHECKDIAG) | WL_STATE.C:153-177 |
| CHASE-003 | **Dogs and Fake Hitler use CHECKDIAG on cardinals too → cannot open doors** | WL_STATE.C:233,253,273,293 |
| CHASE-004 | Door in path: OpenDoor + `distance = -doornum-1`; actor waits until dr_open | TryWalk l. 318-323, T_Chase l. 3158-3166 |
| CHASE-005 | Attack roll per think: point-blank (dist 0, or dist 1 closing <0x4000) chance=300 (certain, RndT max 255); else chance=(tics<<4)/dist | T_Chase l. 3084-3089 |
| CHASE-006 | Dodge: when player visible but attack not rolled → SelectDodgeDir (5 prefs: diagonal-toward-player first, randomized axes), else SelectChaseDir (Pac-Man-style: primary axis toward player, secondary, old dir, random sweep, turnaround last) | l. 3140-3152; WL_STATE.C |
| CHASE-007 | Turnaround forbidden except: dodge first-attack (FL_FIRSTATTACK) or last resort | SelectDodgeDir l. 366-376 |
| CHASE-008 | On reaching tile: position snapped to tile center (round-off fix) | T_Chase l. 3179-3183 |
| CHASE-009 | Spawn ticcount randomized `US_RndT() % tictime` (desyncs animations) | SpawnNewObj WL_STATE.C:85-88 |

### Door area bookkeeping — `WL_ACT1.C` DoorOpening (l. 554-600), DoorClosing (l. 617-672)

| ID | Item | Value |
|---|---|---|
| DOOR-008 | On open start (position 0): both `areaconnect[a][b]++` directions, then ConnectAreas flood | l. 560-585 |
| DOOR-009 | On fully closed: both decremented, ConnectAreas re-flood | l. 640-668 |
| DOOR-010 | Closing aborts → reopen if anything inside door tile or player on it | l. 627-632 |
| DOOR-011 | Areas read from map plane 0 on both sides of door (vertical: x±1; horizontal: y±1) | l. 566-580 |

### Player collision — `WL_AGENT.C` TryMove (l. 801-854), ClipMove (l. 866-897)

| ID | Item | Value |
|---|---|---|
| COLL-001 | Player radius PLAYERSIZE = MINDIST = 0x5800 | WL_DEF.H:88,115 |
| COLL-002 | Wall test: all tiles overlapped by the PLAYERSIZE box; wall = actorat value below objlist ptr range | TryMove l. 807-822 |
| COLL-003 | Actor test: 1-tile-expanded box; blocked if within MINACTORDIST (0x10000) per axis of any FL_SHOOTABLE actor | l. 826-851 |
| COLL-004 | Corner slide: try (x+y), then x-only, then y-only, else stay; HITWALLSND on first block | ClipMove l. 872-897 |

### Level exit / elevators — `WL_AGENT.C` Cmd_Use (l. 1008-1080)

| ID | Item | Value |
|---|---|---|
| EXIT-001 | Use scans one tile in facing cardinal (angle octant test) | l. 1018-1044 |
| EXIT-002 | **Elevator switch only works facing east or west** (elevatorok) | l. 1023,1037 |
| EXIT-003 | Switch flip = `tilemap[x][y]++` (next wall texture) | l. 1062 |
| EXIT-004 | Secret exit: player standing on floor code 107 (ALTELEVATORTILE) → ex_secretlevel, else ex_completed | l. 1063-1066 |
| EXIT-005 | Secret-floor return map: ElevatorBackTo[] = {1,1,7,3,5,3} per episode | WL_GAME.C:39 |
| EXIT-006 | Pushwall trigger: Use on tile whose plane-1 code is 98 | l. 1047-1054 |

### Bosses — `WL_STATE.C` KillActor (l. 855-940), `WL_ACT2.C`

| ID | Item | Value |
|---|---|---|
| BOSS-001 | Points: all bosses 5000 except Fake Hitler 2000, Spectre 200 | KillActor |
| BOSS-002 | Key drops (bo_key1): Hans, Gretel; SoD: Trans, Uber, Will, Death Knight | KillActor |
| BOSS-003 | DeathCam bosses record killx/killy = player position at kill: Gift, Fat, Schabbs, Real Hitler | KillActor |
| BOSS-004 | Mecha→Hitler: A_HitlerMorph spawns realhitlerobj at same tile, HP {500,700,800,900} by difficulty, speed SPDPATROL×5, inherits dir/distance/flags | WL_ACT2.C:2886-2903 |
| BOSS-005 | DeathCam: fizzle to color 127, "let's see that again", camera at killx/killy aimed at boss, backed off 0x14000 stepping until clear, replays death anim; second call (victoryflag) → ex_victorious | A_StartDeathCam WL_ACT2.C:3765-3860 |

### Pickups: treasure/weapons/keys — `WL_AGENT.C` GetBonus (l. 679-744), GiveWeapon (l. 581-590)

| ID | Item | Value |
|---|---|---|
| PICK-008 | Treasure: cross 100, chalice 500, bible 1000, crown 5000 (all treasurecount++) |
| PICK-009 | Weapon pickup: **GiveWeapon = +6 ammo** + upgrade if better; same/lesser weapon → just the 6 ammo |
| PICK-010 | Chaingun pickup: gatling grin (StatusDrawPic slot, facecount=0, gotgatgun=1) | l. 737-744 |
| PICK-011 | Keys: bo_key1..4 → bit in gamestate.keys | l. 679-685 |

### Status face — `WL_AGENT.C` UpdateFace (l. 307-323), DrawFace (l. 270-290)

| ID | Item | Value |
|---|---|---|
| FACE-001 | Look-around: facecount += tics; when facecount > US_RndT() → faceframe = RndT>>6 (0-3; 3 remapped to 1), reset |
| FACE-002 | Health bands: pic = FACE1APIC + 3·((100−health)/16) + frame → 7 blood stages |
| FACE-003 | Dead: FACE8APIC; killed by Schabbs needle → MUTANTBJPIC; SoD god mode → GODMODEFACE |
| FACE-004 | Suppressed while chaingun-pickup sound playing | UpdateFace l. 310-311 |

### Data tables — extracted verbatim to `docs/data/` (tools/dump_charter_tables.py)

| ID | Table | File |
|---|---|---|
| DATA-001 | rndtable, 256 entries | rndtable.json |
| DATA-002 | vgaCeiling: 60 WL6 + 21 SoD per-level ceiling colors; floor fixed 0x19 | ceiling_colors.json |
| DATA-003 | parTimes: 60 WL6 + 20 SoD (bosses/secrets par 0 = "??:??", no par bonus) | par_times.json |
| DATA-004 | statinfo: 56 rows (incl. SoD conditionals) with block/dressing/pickup class | statinfo.json |

## Constants inventory — RESOLVED (batch 4 partial: cheats, 2026-07-26)

### MLI cheat + debug unlock — `WL_PLAY.C` CheckKeys (l. 656-723)

| ID | Item | Value |
|---|---|---|
| CHEAT-001 | MLI (M+L+I held): health=100, ammo=99, keys=3 (both), **score=0**, **TimeCount += 42000 (10 min penalty)**, GiveWeapon(chaingun); all HUD redrawn; overlay message then wait-for-ack, border redraw | l. 658-693 |
| CHEAT-002 | MLI message text (FOREIGN.H:95-99): "You now have 100% Health,\n99 Ammo and both Keys!\n\nNote that you have basically\neliminated your chances of\ngetting a high score!" — font STARTFONT+1 |
| CHEAT-003 | Debug-keys unlock: LShift+Alt+Backspace, gated on cmdline param — WL6: `goobers`, Spear: `debugmode`; message "Debugging keys are\nnow available!"; sets DebugOk | l. 698-723 |
| CHEAT-004 | Spear-only in-game god toggle block with "God mode ON/OFF" message + ENDBONUS2SND | l. 630-652 |
| CHEAT-005 | Tab-key debug set (DebugOk): inventory in WL_DEBUG.C → enumerate at presentation phase |

## Open [VERIFY] items — batch 4 queue

- Ghost movement specifics (T_Ghosts uses SelectChaseDir but which blocking rules? noclip
  claim needs verification against CHECKDIAG path) — WL_ACT2.C:3200-3260.
- T_Stand / T_DogChase deltas from T_Chase (dog must be adjacent to bite) — WL_ACT2.C.
- Episode-end sequences, BJ victory run (victoryflag path, SpawnBJVictory), text screens —
  WL_TEXT.C / WL_AGENT.C VictoryTile / WL_GAME.C.
- Menu structure + cheat codes (MLI, ILM debug keys) — WL_MENU.C, WL_DEBUG.C. (Presentation
  phase; cheats pending user decision.)
- Thrust speed clamp / thrustspeed accumulation details — WL_AGENT.C Thrust.
- SoD routing pass: 21-floor progression, secret floor returns, demo/mission-pack variants
  (m1 data present; check SDMVER/SODVER differences matter only for data detection).
- Save-state field inventory (what must serialize: door timers/positions, pwall state, areaconnect,
  alert/temp2, madenoise is per-frame) — cross-file sweep at Phase 2 start.

## Decision log (Doom-architecture approximations)

Format: ID, what Wolf does, what we do instead, why, gameplay-visibility argument.
Target: zero gameplay-visible entries.

*(empty)*
