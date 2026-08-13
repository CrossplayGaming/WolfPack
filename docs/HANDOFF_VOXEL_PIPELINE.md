# Voxel character pipeline — proven handoff (from Crystal Caves FPS)

Written 2026-08-13. This supersedes the speculative parts of
`HANDOFF_VOXEL_SPRITES.md`: that document designed an approach; this one
records the pipeline that now RUNS, end to end, with a complete character
in-engine. Crystal Caves' player (Milo) ships six states — idle, run,
jump, shoot, pain, death — as 33 KVX models, all produced through this
loop, each hop verified. Wolf's design doc remains useful for its
sprite-fidelity ideas (space carving, the 8-rotation oracle); the
production machinery below is what to copy.

Proven in: UZDoom 4.14.3. Source repo: `F:\CrystalCavesFPS` (commits
`f694547` → `196093a` tell the whole story, including every mistake).

## 1. The toolchain (copy from `F:\CrystalCavesFPS\tools\voxel\`)

| Tool | Job |
|---|---|
| `frame_picker.html` | Browser pose picker (three.js). Load an animated GLB, scrub, mark poses; it emits the `--times` command line. Gotcha already fixed in it: a paused AnimationAction zeroes its timescale, so the mixer is driven via `setTime()` directly |
| `glb_to_obj.py` | Headless Blender bridge. `blender --background --python glb_to_obj.py -- <in.glb> <out_dir> --times 0.0,0.5,...` bakes one textured OBJ per marked pose. `up_axis="Z", forward_axis="NEGATIVE_Y"` on export or models lie sideways |
| `voxelize.py` | OBJ → colored voxels, no external tools: barycentric triangle sampling, UV color, median-cut `.vox` writer, slice/ortho previews. THREE MODES — see §3, the part that took a week to learn |
| `check_vox.py` | Round-trip verifier: parses the written `.vox` like a reader would and renders THAT. Exists because previews rendered from in-memory data cannot catch a writer fault (a truncation bug once shipped models that loaded as their own shadow) |
| `vox_to_kvx.py` | `.vox` → Build KVX: slab encoding, per-slab cull bits, 6-bit 256-color palette, pivots. Self-verifying — every file is parsed back and compared voxel-for-voxel before it ships. Also emits placeholder sprite PNGs (front projection, grAb offsets at bottom-center) |
| `cycle_sheet.py` | Review surface: side views in a row (the cycle read), front views beneath. EVERY set gets a sheet before it ships — two pipeline bugs were caught only by a human looking at one |

Dependencies: Blender (any 4.x/5.x with glTF import; CCFPS uses
`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`), Python
PIL. `voxelize.py` imports `EGA16` from CCFPS's `tools/ccformats/palette.py`
for its `--ega` flag — copy that file too or strip the flag; Wolf art
wants its own palette quantizer anyway (`--sprite <png>` mode quantizes
to an arbitrary sprite's own colors by luminance stretch, which is the
better fit for Wolf).

## 2. The production loop (who does what)

1. **Human**: get an animated GLB per state. Meshy presets for
   non-humanoids; **Mixamo for humanoids** — and Wolf's cast is ALL
   humanoid, so every guard/SS/officer clip retargets automatically.
   One clip per state; never cut one long clip into all states.
2. **Human**: open `frame_picker.html`, scrub, mark poses. Sample at
   8–10 fps of source time; pick EXTREMES (contact/passing, wound-up/
   extended) — voxel resolution destroys in-betweens. Paste the emitted
   command.
3. **Machine**: `glb_to_obj.py` → `voxelize.py` (right mode, §3) →
   `cycle_sheet.py`. About a minute per animation.
4. **Human**: judge the sheet. Trim near-twin frames, name the keepers.
5. **Machine**: `vox_to_kvx.py --name XXXX` → KVX set + placeholder
   sprites → package + VOXELDEF + states (§4–5).

Budgets (full rationale in `F:\GameDev\VOXEL_ANIMATION_PLAN.md`):
15 models = minimum viable actor, 26 = comfortable, 35 = luxe. Voxels
rotate for free, so a 4-frame walk is 4 models, not 32 sprites — death
and attack get 360° views Wolf's sprite sheets never afforded.

## 3. The three voxelization modes — the hard-won part

The mode question is: what do a set's poses share? Getting it wrong is
invisible in previews and wrong in-engine.

| Mode | Invocation | Use for | Why |
|---|---|---|---|
| **Single** | `voxelize.py in.obj out --height 96` | one-off props, statics | pose normalized to its own bounding box |
| **Registered set** | `voxelize.py <obj_dir> <out_dir> --height 96` (+ `--match` to share scale) | grounded sets where the body TRAVELS WITHIN the pose — deaths, planted flinches | ONE union bounding box + one scale for the whole set, so the fall happens in place instead of every pose re-normalizing (a corpse re-normalized to its own box becomes a giant). Writes `frame.json` with the rig-origin voxel coords; `vox_to_kvx` pivots there for X/Y ONLY — a box-center pivot in a sprawl-dominated set visibly teleports the standing frames sideways. Z always pivots at the set's true bottom: a feet-plane z pivot sank the corpse half under the floor ("vanished" in-game), because sprawl poses dip below the rig's feet plane |
| **Per-pose** | `... --per-pose --match <other set's frame.json>` | AIRBORNE or ROOT-MOTION clips — jumps, run-cycles that travel forward | each pose self-grounds (its lowest point = actor origin) so the clip's baked root motion doesn't DOUBLE with the engine's real physics; `--match` borrows another set's scale because a jump clip's union span includes the flight arc, which would silently shrink the body ~15% |

**The heuristic, from the review sheet**: if the body slides through the
frame across poses → per-pose. If the feet stay planted → registered
set. Always `--match` a reference set's `frame.json` so the character is
ONE size everywhere (CCFPS matches everything to the death set, whose
tallest pose is the plain stand).

## 4. Engine format facts (each cost a debugging session)

- **KVX + VOXELDEF is the path** (the Cheello path). Wrote our own KVX
  writer: z grows DOWN; per-column slab runs (ztop, zleng, cull bits,
  palette indices); offset tables relative to the xoffset table start;
  256×RGB 6-bit palette trailing the file; pivots 8.8 fixed point.
  `vox_to_kvx.py` has the spec in comments and verifies every write.
- **VOXELDEF binds sprite+frame as ONE token**: `MILOA = "MILOA" { Scale
  = 0.58 }`. The spaced form `MILO A = ...` fails as a wrong-size sprite
  name (script error per line, voxels silently absent).
- **The sprite frame must EXIST for the state to be valid** — the voxel
  only replaces its rendering. `vox_to_kvx.py`'s placeholder PNGs
  (front projection + grAb bottom-center offsets) satisfy this and give
  a sane fallback if a voxel ever fails to load.
- **Scale**: voxel units render 1:1 with map units × Scale. A 96-voxel
  character over a 56-unit player collision = `Scale 0.58`. Derive
  resolution from the source sprite (Cheello ≈ 1 voxel/pixel; Wolf
  native art is 64 — use 64, or 96 for hero-tier).
- **Flat cartoon colors voxelize far better than photoreal** textures —
  measured across four characters. Bias Meshy prompts that way.

## 5. Engine wiring per state type (player pawn)

CCFPS's `tools/harness/movetest/zscript/ccplayer.zs` is the worked
example. The state-machine shapes:

- **Timed cycles** (idle, run, shoot): plain state loops. The engine
  flips Spawn↔See itself; `PlayAttacking` enters Missile on every shot.
  Match the shoot cycle's tic rate to the run cycle so firing mid-run
  keeps the stride.
- **Velocity-keyed air poses** (jump): NOT a timed cycle. Three states
  (`AirUp/AirApex/AirDown`) each holding one frame at `-1`, switched per
  tic by a `vel.z` bucket (±2 u/tic ≈ a 5-tic apex window); touchdown
  plays a compress+recover `Land` state, then hands back. Ledge
  walk-offs get the fall pose through the same path. Only locomotion
  states are ever overridden — death/pain own the pawn.
- **Pain is punctuation**: the 1–2 strongest recoil poses, ~8 tics,
  `Goto Spawn`. A marked 3-second flinch reads as stunlock in-game;
  keep the rest on disk.
- **Death**: last frame held at `-1` IS the corpse (never model it
  twice); scream/noblocking at the stock beats.
- **THE TRAP — run→idle lives in the engine's FRICTION code.** Native
  `P_XYMovement` calls `PlayIdle()` only when ITS friction zeroes the
  velocity. Any player class with direct velocity authority (CCFPS's
  ramp model — and anything similar) must call `PlayIdle()` itself when
  input releases, or the run cycle loops forever while standing. Key it
  on INPUT, not on reaching zero velocity, or the animation lags the
  stick through the slide. Full write-up in `UZDOOM_PLAYBOOK.md`
  (2026-08-13 entries).
- **Monsters are EASIER**: `A_Chase`/`A_Look` drive See/Missile/Pain/
  Death natively — no friction trap, no velocity keying needed. A Wolf
  guard is: states + KVX set + VOXELDEF. Start there.

## 6. Seeing it: third person + orbit

The review camera that made all of this judgeable came FROM this repo
(chasecam.zs) and went back improved. In CCFPS:
`tools/harness/movetest/zscript/chasecam.zs` —

- chase cam with distance/height on sliders, spherical placement, wall
  trace along the true 3D camera direction;
- **free orbit**: hold a key (`+user1`, bindable) and the mouse swings
  the camera anywhere around the character while facing/aim stay
  frozen. Mechanism (playbook-documented): `InputProcess` receives
  `Type_Mouse` deltas and returning `true` eats them before the view
  turns. InputProcess is UI CONTEXT — accumulate in `ui` fields, flush
  once per tic via `SendNetworkEvent`, apply to play-scope state in
  `NetworkProcess`.

**Back-porting the orbit to Wolf**: the net-event bridge is already the
right shape for lockstep multiplayer, but the orbit STATE must follow
the wolf_skin replication rule like everything else — or gate the
feature SP-only. The plain chasecam needs nothing; it's already Wolf's.

Dev conveniences worth copying: a "Test: die instantly" bind row
(engine's own `kill` command) for judging deaths; `AddOptionMenu
"CustomizeControls"` rows for the toggles.

## 7. Suggested first Wolf target

One guard, minimum-viable budget (~15 models): idle 1, walk 4 (Mixamo
walk, 4 extremes), attack 3 (windup/fire/recover), pain 1, death 6
(last = corpse). All grounded planted sets except nothing — guards
don't jump — so it's registered-set mode + `--match` throughout, the
simplest possible path. Judge against the original 8-rotation sprites
per `HANDOFF_VOXEL_SPRITES.md`'s fidelity ideas if desired; the
pipeline itself no longer depends on them.
