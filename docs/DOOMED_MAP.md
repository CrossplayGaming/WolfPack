# DoomEd number mapping (converter ↔ ZScript contract)

Emitted by tools/convert_udmf.py; Phase 2 ZScript actors must claim these.
Skill flags: converter emits skill1-5; MAPINFO SpawnFilter is positional
(baby=1, easy=2, medium=3, hard=4). Medium-tier spawns (+36/+18 codes) carry
skill3+; hard-tier carry skill4+ (skill5 mirrors hard).

| DoomEd | Actor |
|---|---|
| 1 | Player 1 start |
| 21001/21002 | Guard stand / patrol |
| 21003/21004 | Officer stand / patrol |
| 21005/21006 | SS stand / patrol |
| 21007/21008 | Dog stand / patrol |
| 21009/21010 | Mutant stand / patrol |
| 21020–21026 | Hans, Gretel, Gift, Fat, Schabbs, Fake Hitler, Hitler |
| 21030–21035 | Spectre, Angel, Trans, Uber, Will, Death Knight (SoD) |
| 21040–21043 | Ghosts: Blinky, Clyde, Pinky, Inky |
| 21100+i | Static object, statinfo index i (docs/data/statinfo.json; class there decides block/pickup/dressing) |
| 21200+d | Patrol turn arrow, dir d in E,NE,N,NW,W,SW,S,SE |
| 21210 | Pushwall marker (slab emission: polyobject pass) |
| 21211 | Victory trigger tile (MAP-017) |
| 21212 | Dead guard decoration |

Sim data not carried as things (in MAPnn.manifest.json): per-tile area grid,
sector↔area mapping, door records (axis, lock, slide dir, pocket tile),
ambush tile list. The ZScript sim loads the manifest-derived lump (Phase 2)
for area-based sound propagation and ambush flags.
