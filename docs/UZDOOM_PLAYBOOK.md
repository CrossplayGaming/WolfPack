# UZDoom Engine Playbook

Living document of engine facts and best practices earned across the
WolfDoom, CatacombDoom, and HovertankDoom projects. Everything here was
learned by hitting the problem, not by reading about it. Update as new
lessons land; entries carry the symptom they present so future sessions
can search by what they're seeing.

**Prime directive:** the engine's ZScript sources are readable inside
`engine/uzdoom.pk3` (`zscript/engine/ui/menu/*.zs` etc.). Read them
instead of guessing an API — every API guessed in these projects was
wrong (Init signatures, VirtualToRealCoords arity, ClearMenus existence).

---

## 1. 2D drawing (the transform minefield)

- **`DTA_DestWidthF/HeightF` + real-pixel positions are honoured
  EXACTLY.** This is the one transform that means the same thing in
  every context (Menu, StatusScreen, overlay). Canonical path for
  pictures. Use `TexMan.GetSize`, not `GetScaledSize` (the latter
  carries engine texture scaling).
- **Virtual screens (`DTA_VirtualWidth/Height`) map onto the centred,
  aspect-corrected 4:3 box — NOT the display.** Plain virtual 320x200 is
  correct for text. Widening the virtual width "to span the screen"
  squeezes content by 320/VirtW (rendered all pregame art square once).
- **`DrawText` silently ignores `DTA_ScaleX/ScaleY`.** To draw text into
  an arbitrary rect, draw glyph-by-glyph with `Font.GetChar` +
  `GetCharWidth` through the DestWidth path.
- **`DTA_320x200` and `DTA_KeepRatio` scale differently in a
  StatusScreen than in a Menu**; KeepRatio stretches rather than
  pillarboxes. Avoid both; use the two calibrated paths above.
- **A StaticEventHandler's `RenderOverlay` on a title level can `Dim`
  but its `DrawTexture` calls never reach the screen.** Full-screen
  front ends must be Menus (which also get input for free).
- Measure, don't reason: draw known DestWidths against a full-window
  reference rect (magenta Dim) in ONE frame and read the capture.

## 2. Menus

- **Overriding the `"MainMenu"` MENUDEF descriptor buries the engine
  menu** — Esc in game and title keys land on your class. Every custom
  ListMenu needs its own `LISTMENU "Name" { Class "X" }` descriptor so
  `Menu.SetMenu` finds it.
- **A MENUDEF `Class` naming a class that exists on disk but is not
  `#include`d dies as a silent M_Init fatal** — log ends at
  `M_Init: Init menus`, error only in a GUI dialog. Same signature for
  any MAPINFO/MENUDEF parse fatal (e.g. `endgame {}` blocks,
  `OptionMenuSettings`, both rejected by this engine).
- **`MessageBoxMenu.Init` takes SIX params** (parent, message, mode,
  playsound, cmd, native_handler). Drop the last two in an override and
  quit/endgame confirms silently stop working — the exit action lives
  there. `gameinfo messageboxclass` restyles all engine confirms.
- **No `ClearMenus` in ZScript.** Close the whole stack with a
  `GetCurrentMenu()/Close()` loop.
- **Start games with `Menu.StartGameDirect(false,false,null,ep,skill)`**
  (UZDoom extension, indexes the MAPINFO episode list — define ALL
  episodes). `ChangeLevel` from a titlemap drags `GS_TITLELEVEL` into
  the new map: no status bar, every key reopens the menu.
- ui code cannot touch play state: bridge with
  `EventHandler.SendNetworkEvent` → `NetworkProcess` play-side.
- **Recoloring engine pages:** `gameinfo dimcolor/dimamount` (kills the
  purple wash), `menufontcolor_*` keys + a TEXTCOLO lump. **TEXTCOLO
  ranges must be GRADIENTS (black → target):** flat single-color ranges
  recolor the glyphs' built-in dark outlines too and erase them.
- `gameinfo CursorPic` sets the menu mouse cursor (top-left hotspot).
  Mouse interactivity = override `MouseEvent(type,x,y)` and invert your
  own drawing transform back to layout units.
- Engine option pages hardcode `NewSmallFont` (`Menu.OptionFont`);
  folder-font replacement of it did NOT take effect here.

## 3. MAPINFO / structure

- Standalone IPK3s must declare `statscreen_*` classes or transitions
  abort; `borderflat` + `border` express the view surround (Wolf's
  bevel = generated 1px pieces, zero drawing code).
- `next = "EndTitle"` skips the intermission — fatal if your episode-end
  screen lives there. Keep a placeholder `next` and own the flow in the
  StatusScreen.
- StaticEventHandlers MUST be listed in `gameinfo EventHandlers` or
  they silently never run.
- Archived config values beat DEFCVARS **and** `nosave` declarations
  (nosave stops writing, not loading an existing line). Launchers must
  force critical cvars with `+set`. One debug session can poison every
  later launch through the config.

## 4. ZScript gotchas

- Reserved words hit so far: `action`, `auto` (case-insensitive),
  `states`, `out`. Field/method name collisions with inherited members
  also error (`areabyplayer`, `Drawer` duplicates from botched edits).
- Virtual overrides may not restate default parameter values, and must
  match the full base signature.
- Sprite lumps don't register sprite NAMES: without a never-entered
  `States` block naming them, `GetSpriteIndex` returns -1 and a
  -1-sprite actor entering view hangs the renderer.
- Pickups: `Inventory.TryPickup`, not `Touch` (never fires on plain
  Actors); `Inventory` does not default `+SPECIAL`.
- `A_ReFire`'s parameter is the FLASH state, not a jump target.
- `String.Format("%d%%")` does not emit a literal `%`.
- Lump names cap at 8 chars — longer names fail silently.
- Overriding an engine virtual WHOLESALE drops its hidden side
  effects. Symptom: a nearby feature dies with no error and every
  config knob for it looks broken. The stock `MovePlayer` computes
  `player.onground` (engine player.zs:1299); replacing it for
  zero-inertia movement left onground permanently false, which made
  `CheckJump` silently refuse at every sv_jump value — two rounds of
  cvar debugging chased a physics bug. Before overriding, read the
  stock body end to end and inventory every assignment that outlives
  the call (player fields, flags, counters), then re-emit the ones the
  replacement doesn't obsolete.
- Map-spawned actors run `PostBeginPlay` on the first TICK - AFTER
  `WorldLoaded`. Mutating actor state from `WorldLoaded` that
  `PostBeginPlay` also writes (e.g. fields copied from `args[]`) gets
  silently overwritten. Either mutate on the first `WorldTick`, or put
  the conditional in the actor's own `PostBeginPlay` (how the DM door
  unlock landed). Caught only because a probe counted 0 where 1 was
  expected - count your sweeps.
- `static const` arrays need the class-qualified name inside STATIC
  methods ("Unknown identifier" otherwise; instance methods see them
  unqualified).
- Userinfo cvar writes (`color`, custom `user` cvars) are legal ONLY
  from menu code - a `UiTick` write VM-aborts every tick ("Attempt to
  change CVAR outside of menu code"). Sync userinfo on menu entry, or
  pass `+set` at launch.
- Probing input from `WorldTick` doesn't work: it runs after
  PlayerThink consumed the tic's cmd, and the net stream rebuilds
  `player.cmd` next tic, so `cmd.buttons |=` injections vanish. Drive
  the handler directly (set the button, call `CheckJump()` in the same
  tick) — same code path a real press takes.

- **Netgame client prediction re-runs the local player's `Tick` and
  `PlayerThink` several times per frame, then restores the PAWN - not
  global state.** Any Tick side effect on shared sim state (an RNG
  stream, doors, level exit, handler fields) advances differently on
  each node and desyncs the lockstep - symptom: "Out of sync with:
  Player (N)", positions still agreeing while derived events (damage
  rolls, kills) differ per node. Guard with the engine's own pattern:
  `if (player.cheats & CF_PREDICTING) return;` before anything
  non-movement. Proof protocol: a gated beacon printing tic + RNG
  index + player state on every node, diffed across logs - divergence
  showed at the FIRST sample with both players standing still.

- **Not all of a game's art is in the game palette.** Spear's title
  halves and nine ending screens each carry their OWN palette chunk;
  decoded against the game palette they render like a photo negative.
  Guard it structurally: every `*PALETTE` chunk in the graphics enum
  must be applied to some picture or explicitly listed as unused. A
  hand-kept list goes stale - the ending screens were handled and the
  title was missed by the same author in the same session.
- **Parsers that filter by naming convention silently DROP malformed
  entries and shift every index after them.** id's WL_DEF.H sprite enum
  contains a typo - `MACHINEGUNATK3` missing its `SPR_` prefix - and a
  regex matching only `SPR_*` skipped that slot, shifting the chaingun
  by one in BOTH games. Symptom: one weapon wears another's art.
  Enumerations parsed out of source MUST be length-checked against the
  data they index (parsed names vs VSWAP sprite count); that single
  assertion catches every drop instantly, and self-consistent audits
  built on the same parser cannot.
- **Existence checks cannot catch a wrong-content index.** Porting two
  data sets (WL6 + Spear) through one pipeline, every bug was the same
  shape: an index that resolves to a REAL lump in both games but the
  wrong art/sound in one. "Is every referenced lump present?" returns
  clean while doors render as rock. Audit derived constants by
  RE-DERIVING them from each data set and rendering what they select
  (tools/audit_assets.py). Anything computed from data layout -
  DOORWALL = PMSpriteStart - 8, weapon bases, the dead-guard chunk -
  must be derived per set, never hardcoded from whichever game you
  built first.

## 5. Testing & verification harness

- `+quit` runs before the game loop: to prove a map loads, poll the
  logfile for a map header, then kill the engine.
- **Self-tests must not share a floor ungated:** test subjects and the
  player need `bINVULNERABLE` (stray fire kills the subject, or the
  subject kills the player and the death sequence restarts the floor,
  wiping the test).
- **Never assert at a fixed tic against RNG-driven behavior** (reaction
  times are random): latch-poll a window and pass on first success.
- **`areabyplayer` follows door connectivity, not teleports.** Tests
  that move the player must stay in (or account for) the player's area
  or sight/wake logic can never trigger.
- Screenshot protocol: `SetProcessDPIAware` first; capture the WINDOW
  rect, not a hardcoded region; always include an in-frame reference
  rect; the NVIDIA overlay (top-right, ~8s) reads as content; the user
  actively uses the machine — don't fight for focus, hand them the test.
- Debug prints that gate the harness must themselves be cvar-gated or
  they print over normal play.
- **Unattended map-load validation works; unattended FRAME CAPTURE does
  not.** (4.14.3, Vulkan, measured on CatacombDoom's package from the
  CrystalCavesFPS project.) What works: `+logfile <path>` for the whole
  log, `+map X` to pick the map, and a `-file` pk3 whose
  StaticEventHandler prints markers from inside the loaded map — poll the
  log for those, then kill. Register it with **`AddEventHandlers`** in a
  MAPINFO `gameinfo` block; that APPENDS, where `EventHandlers` would
  replace the host game's list and silently unregister its handlers.
  What fails: startup `+commands` all execute BEFORE the game loop, and
  console `wait` does not defer them (`+wait 350 +quit` lived 1.4s vs
  1.6s for `+quit` alone) — so `+map X +screenshot +quit` never draws a
  frame. And `LevelLocals.MakeScreenShot()` (doombase.zs:492) produces
  NO file when called from a loaded map: the marker proves the call is
  reached, but nothing lands in the shot dir, the engine dir, or the user
  profile, windowed or fullscreen, with nothing logged even at
  `screenshot_quiet 0`. Screen capture (the `cap.ps1` approach) remains
  the only route to pixels, and it needs the foreground — so treat
  visual capture as attended and design review harnesses around
  artifacts that need no engine (top-down renders from level data).
- **`StaticEventHandler` hooks take an event parameter.** `WorldLoaded`
  is `virtual void WorldLoaded(WorldEvent e)`; overriding it with no
  parameter fails as "Attempt to override non-existent virtual
  function", which reads like the hook doesn't exist rather than like a
  signature mismatch. `WorldTick()` genuinely takes none. Read
  `zscript/events.zs` for the full list.
- **Over-broad error patterns in a log-polling harness turn warnings
  into failures.** Matching bare `Unknown` caught the benign "Unknown
  texture: F_SKY1" that a perfectly loadable package emits, aborting the
  run and reporting a false negative. Match only strings that genuinely
  stop the engine ("Execution could not continue", "VM execution
  aborted").

## 6. Assets & pipeline

- IPK3 lumps shadow engine lumps — EXCEPT anything the engine reads
  before wads mount (the launch banner `widgets/banner.png`; patching
  the engine pk3 itself did not visibly take either — unresolved,
  parked).
- PNG offsets via `grAb` chunks; fonts as folder fonts named by hex
  codepoint (glyph masks tinted at draw time with `DTA_ColorOverlay`).
- Python tooling on Windows: `write_text` defaults to cp1252 — an
  em-dash in generated code becomes `0x97` and breaks the file. Keep
  generated source ASCII or pass `encoding`.
- Always route builds through one script that re-runs asset generation;
  stale-asset "fixes that didn't take" cost days across projects.

## 7. Process rules that earned their place

- Measure before asserting; when a report contradicts your model, the
  capture/harness is as suspect as the code.
- On any silent startup death, check the log's LAST line: `M_Init` =
  MENUDEF, `G_ParseMapInfo` = MAPINFO, `LoadActors` = ZScript.
- Verify byte-for-byte, not by proxy (banner "verified" by size matched
  the old file's size).
- Slice-edits on ZScript files corrupt easily; prefer anchored
  string-replace with asserts, and `git checkout` the file rather than
  patch a mangled state.

## Standalone IPK3 minimum furniture (Crystal Caves FPS shell, 2026-07-31)

Booting an IWADINFO+MAPINFO-only ipk3 dies with a BLANK fatal dialog (the
log ends right after the wad-add lines, no message anywhere). Measured by
lump bisect, a standalone needs, in failure order:

1. **PLAYPAL** -- the actual blank-dialog fatal. Any 256-entry palette
   works if all art is truecolour PNG; only existence matters.
2. **Own episodes and skills** -- with none defined, Doom's inherited lists
   survive, and anything downstream saying `clearepisodes`/`clearskills`
   (our capture harness does) fatals with "you cannot use clearX ... if you
   do not define any new X after it."
3. **MENUDEF overriding MainMenu/EpisodeMenu/SkillMenu with TextItems** --
   the stock menudef's PatchItems reference M_DOOM/M_NEWG/... which do not
   exist without Doom's art. NOTE: the stock lump still PARSES first and
   logs one "Script error" per missing patch even when overridden; ship
   1px placeholder graphics under those names to keep logs clean.
4. **borderflat + the eight brdr_* pieces** -- otherwise every frame at
   screenblocks<11 spams "Unknown texture brdr_b".

Corollary caught the same night: our capture harness treated "Script
error," as a FATAL hint and killed every run against the new shell --
script errors are per-lump warnings the engine survives. True fatals carry
"Execution could not continue" / "VM execution aborted" / "Fatal error".
The over-broad-log-pattern lesson, third occurrence.

Also proven here: the borrowed-base era is over cheaply. IWADINFO's
`Config` key gives the game its OWN cvar namespace, so a fresh shell means
fresh defaults -- no inherited nojump, no foreign HUD, no archived-cvar
poison from sibling projects.

## Reusable pattern: in-game tuning sliders (Crystal Caves FPS, 2026-07-31)

Eric flagged this as a keeper for ANY future FPS-style project. Feel
constants (speed, jump, gravity, ramps, view bob) cannot be tuned by
reading numbers -- the designer needs hands on the game while the numbers
move. The pattern, four pieces, all data-driven:

1. **CVARINFO**: one `server float` per tunable. Server cvars archive to
   the config by default, and the standalone shell''s own IWADINFO
   `Config` namespace means the archived values belong to THIS game.
2. **MENUDEF**: an `OptionMenu` of `Slider` items bound to those cvars,
   reachable from the pause menu (`TextItem "Tuning", "t", "YourMenu"`
   in MainMenu). Sliders write cvars live, no restart.
3. **Player class**: read the cvars each tic in PlayerThink and apply
   (JumpZ, Gravity, ForwardMove1/2, ViewBob...). FindCVar per tic is
   cheap; engine field names verified against uzdoom.pk3''s player.zs.
4. **The workflow**: designer plays, slides, exits; the config archives
   everything; the session then reads the archived values back and
   freezes them into the constants file. Tuning session = one playthrough.

Bonus lesson from proving it: SendKeys never reaches the engine (raw
input) -- to screenshot a menu unattended, launch with
`+wait 105; openmenu YourMenu` instead.

Reference implementation: F:\CrystalCavesFPS tools/build_base.py
(CVARINFO + MENUDEF blocks) and tools/harness/movetest/zscript/ccplayer.zs.

## Third-person camera (chasecam.zs)

- `player.camera` is SHARED SIM STATE, not a render preference. Public
  third-person mods assign it from `consoleplayer` only - single-player
  thinking. In lockstep MP, derive it on every node for every player
  from a replicated user cvar (the wolf_skin pattern) and maintain it
  in the pawn's Tick AFTER the CF_PREDICTING guard.
- Once `camera != mo` the engine does the two hard parts itself: the
  player's own sprite renders (8-rotation skin required) and the
  first-person weapon overlay + crosshair are suppressed. No flags.
- Camera actor: +NOINTERACTION, no Super.Tick(), position = pure
  function of the owner recomputed per tic; `SetOrigin(pos, true)`
  keeps render interpolation so the glide is framerate-smooth.
- Pull in off walls with the OWNER's LineTrace (angle+180,
  TRF_THRUACTORS) - tracing from the camera actor itself starts the
  trace outside the world after a fast turn and returns garbage.
- Interplay: any feature that repositions the pawn for a cutscene (the
  boss DeathCam) must suspend third person, or the chase cam films the
  camera stand.
- Headless two-node netgames (`-host 2`/`-join localhost`, no visible
  windows) stall after "Selected peer to peer networking mode" and
  never load the map, even with separate -config files and
  i_pauseinbackground 0. Visible-window instances (mp_launch.ps1) work.
  Sync-verify MP features with the real dual-window path.

## Probe-harness gotchas (elevator false alarm, 2026-07-31)

- The console `warp` teleport does NOT trigger touch specials - a
  pickup probe that warps onto an item tests nothing. Walk into it
  (+forward) like a player would.
- A successful level exit is INVISIBLE in the logfile: the stat screen
  isn't a map, so judging "did the exit fire" by the absence of the
  next map's title line concludes 'broken' for working exits. Judge by
  screenshot (the stat screen's flat teal is trivially detectable) or
  by the next map's onmap debug line after advancing.
- The WOLFDBG beacon's rng index wraps mod 256; a wrap (226 -> 1) reads
  exactly like a fresh-map reset. The handler's own t counter resets
  per level and the beacon prints both - t continuous + rng small means
  WRAP, not reload.
- `changemap` silently does nothing in single player here; `map` works
  once sv_cheats is set.
- **The player pawn TRAVELS between levels with all custom fields
  intact** (G_StartTravel/FinishTravel) - a one-shot latch field set
  during level N is still set on level N+1. WolfUse's `exiting`
  debounce silently refused every elevator after the first until
  cleared on WorldLoaded. The trap in testing: `-warp` and fresh-map
  probes spawn NEW pawns (latch clear), so every harness run passes
  while every real playthrough fails from the second floor on. When a
  user report and a probe disagree, ask what state the pawn CARRIES
  that the probe's pawn does not.

## Generated sprite lumps (the grAb lesson, 2026-07-31)

- **PIL re-saves strip the grAb chunk** (sprite origin offsets). A
  sprite PNG without grAb still loads and installs - it renders
  DISPLACED far out of view, which presents as invisible. Two full red
  herrings were chased first (frame registration, transparency
  structure); the tell that finally convicted it: a byte-copied
  original under the new name rendered, a pixel-identical PIL re-save
  did not. Every tool that writes sprite PNGs must splice the source's
  grAb (or write one) into the output.
- Frame swapping on one sprite name (actor.frame = 1 with only frame A
  in States) does not render even when the B lump exists and
  CheckForTexture validates it. Give variants their own 4-char sprite
  name, registered by a dormant States block, and swap actor.sprite
  via the index from that class's own FindState().sprite.
- Console `summon` probes: the actor spawns at a fixed distance ahead
  - inside door slabs or stacked on a prior summon if aimed poorly.
  Two isolation tests were invalidated this way. Face open floor, one
  summon per run.

## Solid 3D floors, driven and verified from outside (GameBuilder, 2026-08-01)

- **Sector_Set3dFloor (160) type 1 solid, measured on 4.14.3: the
  control sector's FLOOR height is the slab's bottom and its CEILING
  height is the slab's top.** (Modder lore says "inverted sector" often
  enough to doubt it; the engine's own numbers settle it - see the probe
  below.) Args on the control line: arg0 tag, arg1 1, arg2 0, arg3 255.
  Sides render from the control line's sidedef texture; the control
  sector's flats paint the walking surface and underside - set both to
  the slab texture and either mapping looks right.
- Control-sector machine room: a strip strictly OUTSIDE the playable
  bounds (one-quantum gap, boxes spaced a quantum apart) keeps the
  coincident-linedef defect class impossible. UDMF `id = N` on the
  target sector, no tag on the control sector itself.
- **Geometry is verifiable from inside with no capture:**
  `Level.PointInSector(pt)`, `sector.Get3DFloorCount()`,
  `sector.Get3DFloor(i).bottom/.top.ZatPoint(pt)` (mapdata.zs), printed
  as log markers. A harness asserts slab heights the engine itself
  measured - this convicted/acquitted the height mapping above in one
  run.
- **VM-abort log signatures differ by hook.** An abort in `WorldTick`
  logs `VM execution aborted: ...` to +logfile and the engine keeps
  running (the fatal-pattern match catches it). The SAME abort in
  `WorldLoaded` (map setup) never gets its headline into the logfile -
  only the `Called from ...` stack line lands - and the engine dies or
  hangs on its error dialog. Log-polling harnesses need all three
  detection routes: fatal-pattern match, process-exit, marker timeout.
- **Windows locks the loaded package: `os.replace` onto the ipk3 a
  running engine holds raises PermissionError.** Live-reload by
  swapping the file under the engine is impossible on top of all the
  console-injection dead ends (changemap dead in SP, no external
  command channel). Blink-reload is therefore relaunch-with-position:
  versioned packages (preview-NNNN.ipk3), position captured from
  periodic handler markers, passed back via `+set gb_spawn_*`
  (noarchive cvars), restored first WorldTick with `SetOrigin(dest,
  false)` + angle/pitch. Measured: restore is EXACT (delta 0.0 units /
  0.0 deg); full blink terminate->standing-again ~2.6 s windowed.
- Base-IWAD runs (same maps as -file over freedoom2/DOOM2) load the
  same 3D-floor geometry with identical measured heights, zero script
  errors - and the engine QUIETLY ADDS CONTENT: next to a Steam-owned
  DOOM2.WAD it auto-loaded the rerelease's id24res.wad from the Steam
  library; freedoom2 auto-applies its embedded DEHACKED. A preview
  harness (or launcher) over user IWADs must expect extra lumps it
  never asked for, and IWAD runs get the per-IWAD config, NOT the
  shell's own Config namespace - per-session -config plus forced +set
  is the only poisoning defence there.
- **An unfocused engine window auto-pauses the sim: WorldTick stops,
  so handler markers FREEZE while WorldLoaded still prints.** Symptom
  (2026-08-01): an engine launched while another window held focus
  logged map_loaded but never one GB_POS - reads exactly like a broken
  marker/parse path, and it is intermittent because it depends on which
  window Windows gives foreground to at spawn. Bites twice in an
  editor-preview shape: harness engines spawned back-to-back, and the
  REAL use case where the user clicks the app/console window to type
  (preview backgrounds -> world freezes -> position stream goes
  stale). Force `+set i_pauseinbackground 0` on every launch; a
  preview loop requires a live sim by design. (The MP-headless note
  above touched this cvar; this is the single-player, foreground-rules
  form with the marker-freeze symptom.)

### Things ON 3D floors: UDMF `height` just works (GameBuilder, 2026-08-02)

Measured on 4.14.3 over a real DOOM II IWAD, six planted cases, engine's
own `GB_ACTOR` account - not reasoned about, because modder lore treats
"things on 3D floors" as a known-awkward corner.

- **A map thing given UDMF `height = N` in a sector carrying a
  Sector_Set3dFloor slab whose TOP is at N SPAWNS RESTING ON THE SLAB.**
  No special flag, no dummy sector, no post-spawn nudge. Measured:
  single slab 0-32, `height = 32` -> actor `pos.z` 32.0; two-slab stack
  0-32 + 32-64, `height = 64` -> 64.0. It also holds through the SPAWN
  clamp - the actor's own `floorz` comes back as the SLAB TOP (32.0 /
  64.0), not the sector floor, so the engine agrees the 3D floor is what
  it is standing on. `pos.z == floorz` is the assertion worth making:
  position alone cannot tell resting from hovering, and `floorz` can.
- **It stays.** Same actors sampled again 105 tics later with the world
  running: identical z. A thing merely POSITIONED at the right height
  would have fallen within the second.
- **A raised thing whose slab is later removed simply falls** - normal
  gravity, no error, nothing special. That makes "leave it alone" a
  legitimate editor answer to deleting the platform under something.
- **`height` on a SPAWNCEILING actor measures DOWN from the ceiling.**
  Measured: 52-tall Hanging Leg (`Meat5`), ceiling 256 -> `height` absent
  gives z 204.0 (top flush on the ceiling); `height = 32` gives z 172.0.
  So one key covers both directions and the engine picks which by the
  actor's own flag - the description never has to name a convention.
- **A raised thing on a TERRACE needs no `height` at all**: raised
  ground is the sector's own floor, so the thing's anchor plane already
  moved. `height` is only for surfaces the sector floor does not
  describe.
- `AActor.floorz` / `AActor.ceilingz` are readable from ZScript and worth
  putting in any actor-probe marker for exactly this reason.
- Watch the name, not the id: the catalog row for editor number 53 is
  `Meat5`; "HangingLeg" is not a class in this engine. Same
  a-name-is-not-a-name trap as `ZombieMan` / `Zombieman`.

## The connection layer: in-engine aim, ghost, clicks (GameBuilder, 2026-08-01)

- **`Console.PrintfEx(PRINT_LOG, ...)` reaches the `+logfile` file
  WITHOUT touching the on-screen notify area.** Machine markers at a
  sub-second cadence were silently spamming the player's screen through
  plain Printf; PRINT_LOG keeps the log-polling channel fully intact
  (every harness marker still parses from the file) and the screen
  clean. Player-facing feedback goes through `Console.MidPrint`.
- **A play-scope helper called from a ui hook (RenderOverlay) dies at
  load with "Can't call play function X from ui context."** Declare
  shared helpers (cvar readers etc.) `clearscope static`.
- **Asset-free hologram: `Level.SpawnParticle(FSpawnParticleParams)`
  with absolute positions, no texture, STYLE_Add, SPF_FULLBRIGHT,
  lifetime 2, respawned every WorldTick** draws a crisp wireframe box
  (12 edges, a point every 8 units) with zero art and zero
  interaction. Updates at tic rate: the ghost trails the view by at
  most one tic (~29 ms); lifetime 2 leaves up to one tic of trail
  during fast swings.
- **Aim traces against live level geometry from ZScript with a
  fixed-step march** (`Level.IsPointInLevel` + `PointInSector` +
  plane `ZatPoint` + `Get3DFloor`), no AimLineAttack needed -- and the
  semantics matter: IsPointInLevel is FALSE below a sector's floor and
  above its ceiling, so a ray into a riser face stops at the riser's
  base (the Minecraft side-face answer). Two measured traps: (1) a
  sample landing EXACTLY on a boundary line counts as inside the open
  sector for the engine while `floor(x/q)` cell math assigns it to the
  far (wall) cell -- nudge the deciding sample half a unit back along
  the ray before deriving the cell; (2) when a Python mirror of the
  rule must agree with the ZScript (parity harness), compare SAME-TICK
  marker pairs (pos + aim printed back to back): pairing makes the
  check immune to a live human moving the mouse in the test window --
  which happened repeatedly on this in-use desktop and once exposed a
  real divergence a fixed pose would have missed.
- A DoomPlayer subclass declaring its own `Player.StartItem` list
  boots clean as a WEAPONLESS player, freeing fire/alt-fire for editor
  clicks read off `players[0].cmd.buttons` edges. Boot-verified; the
  physical click path itself still awaits a human hand -- input
  injection does not exist, so no harness can press fire.
- **Menu writes to user cvars via `CVar.GetCVar(name, player)` apply
  for the session but NEVER ARCHIVE.** That call returns the
  per-player userinfo VIEW; SetInt on it updates the live value (and
  replicates) but the base cvar - the one the ini dumper reads on
  clean exit - keeps its old value. So every menu-set option silently
  reset on relaunch while console `set` (which writes the base)
  persisted fine. Menus must write through `CVar.FindCVar(name)`; the
  base write propagates to the userinfo copy exactly like a console
  set. Reads-after-write must also use the base: the view lags a sync
  tick behind. Proven by an in-engine probe (below): in-session 1,
  archived 0 before the fix; 1/1 after.
- **SendKeys-style window automation does not reach this engine's
  menus at all.** OS-level screen captures showed every scripted
  keystroke landing in gameplay - months of "menu navigation" probes
  were keys raining into the sim, returning plausible-looking but
  meaningless results. Drive menu-path tests from INSIDE instead: a
  dev cvar (`+set wolf_dbg_autotoggle 1`) makes the menu press its own
  row via the exact Adjust path a real keypress takes, then Close();
  `openmenu X` from an exec cfg opens it without any keystroke. Two
  gotchas: console `wait` counts game tics, which freeze while a menu
  pauses SP - the probe menu must close itself or the cfg's quit never
  fires (and a forced kill skips the ini archive, ruining persistence
  tests). And OS captures need `SetProcessDPIAware()` or a 125%-DPI
  desktop crops the grab.
- **Widget-menu scrolling (wolfwidgets.zs): clamp the scroll offset in
  Drawer, not in input handlers.** Drawer-time clamping tracks sel no
  matter how it moved (keys, wrap-around, mouse hover). Draw the
  visible slice (`i = r + scroll`), shift the cursor base by
  `-scroll * 13`, translate mouse hits by `+scroll`, and derive the
  frame height as `winH - 13 * hiddenRows` so pages that pad winH for
  extras (crosshair preview) keep their padding. Scroll arrows live in
  the gutter OUTSIDE the frame edge - inside collides with the
  right-aligned key/value column.

## Key bindings from outside the engine (GameBuilder alt-fire hunt, 2026-08-01)

Wanting to GUARANTEE two binds (mouse1 +attack / mouse2 +altattack are
the editor's build/undo controls), three channels were measured; two
are dead:

- **Launch-line `+bind key cmd` is INERT.** Binding init runs after
  the +command batch and overwrites it - a sabotage `+bind mouse2
  +strafe` AND a protective bind both vanished; the engine reported
  the default either way. (+commands-run-early does not mean they WIN.)
- **`Bindings.SetBind` outside menu code is FATAL**, not a no-op:
  "Attempt to change key bindings outside of menu code" kills the
  engine mid-WorldLoaded. Same guard family as the userinfo-cvar-write
  trap above. `GetBinding`/`GetKeysForCommand` READ fine from play
  scope - report, don't heal, from handlers.
- **The config's `[<Config>.Bindings]` section is the working
  channel** - entries apply verbatim (a poisoned Mouse2=+strafe
  demonstrably took effect). Patch the file BEFORE launch. Caution: a
  bindings section REPLACES defaults, so never CREATE a partial one -
  patch keys inside an existing section only; a config with no section
  gets engine defaults, which on a virgin Config-namespace ini are the
  WASD defbinds set (mouse1 +attack, mouse2 +altattack - measured, so
  fresh-per-session configs are already correct).

Related measurements from the same hunt:
- **Launch-held button +commands (`+attack` as an arg) do not survive
  into the map** - button states are cleared at level start, so
  cmd.buttons cannot be pre-pressed for a harness. The physical click
  really is untestable without a hand; instrument instead (a GB_BTN
  marker on every cmd.buttons change convicts or clears the input
  layer in one manual run).
- **The engine's +logfile is opened write-SHARED, but external appends
  get clobbered**: the engine keeps writing at its own tracked offset,
  overwriting whatever another process appended. Log-line injection
  into a live session is unreliable; unit-test the consumer with
  synthetic text instead.

## Add-on gameinfo over a real IWAD (GameBuilder SETUP-02, 2026-08-01, UZDoom 4.14.3)

- **A `-file` add-on's MAPINFO `gameinfo { playerclasses = "X" }`
  REPLACES the base game's player-class list over a real IWAD** -
  measured: the GameBuilder preview add-on over freedoom2.wad spawns
  `GBPreviewPlayer` (weaponless editor player), proven by a
  first-tick `GetClassName()` log marker, zero script errors. So the
  fire/alt-fire editor loop works identically over IWADs and the
  standalone shell.
- Same boots reconfirmed the isolation recipe for IWAD runs (no
  IWADINFO Config namespace there): per-session `-config` + forced
  `+set` -- with a fresh ini the engine's own defbinds land correct
  (mouse1 +attack / mouse2 +altattack), so the binds gate stays green
  with no bindings-section patch needed.
- Corpus-adjacent detection fact (not engine behavior, recorded once:
  Steam's BFG Edition DOOM.WAD/DOOM2.WAD carry **PWAD** magic yet the
  engine treats them as IWADs by content -- identity tables must let a
  blessed hash outrank the header magic).
- **The converse, also measured (GameBuilder PLAY-01, 2026-08-01):
  OMITTING `playerclasses` from an add-on's gameinfo leaves the base
  game's own default player-class list in force** -- the play-test
  flavour of the same add-on over freedoom2.wad spawns plain
  `DoomPlayer` (first-tick GetClassName marker, zero script errors,
  weapons/health as the base game ships them). So one add-on family
  can swap player behaviour per build flavour with a one-line MAPINFO
  difference and no ZScript: declare `playerclasses` to replace the
  list, omit it to inherit the base game's.

## Whole-map geometry dump probe (GameBuilder FMT-02, 2026-08-01, 4.14.3)

Widening the single-point 3D-floor probe to the whole map, for verifying
generated curved geometry (segment fans) from outside:

- **`Level.Vertexes` is enumerable from ZScript** (`Level.Vertexes.Size()`,
  `.Vertexes[i].p`) and holds MORE vertices than the UDMF file: the
  engine's internal node build adds split vertices (measured: a 72-vertex
  TEXTMAP reported 104). Harnesses must therefore assert their computed
  vertices are a SUBSET of the engine's (within 0.01 u), never an exact
  count match. Float UDMF vertices written at 3 decimals came back exact.
- **Sector order and indices are preserved from TEXTMAP file order**
  (`Level.Sectors[i]` is the i-th `sector{}` block) -- computed sector
  indices can be compared against the engine's directly.
- `plane.ZatPoint` reports a heightfloor of 0 as `-0.000000` in printf --
  compare numerically, never by string.
- One-sided hole loops (freestanding wall rings whose front sidedefs
  reference the CONTAINING sector, playable on the right of v1->v2) and
  3-decimal float vertices both load clean through the UDMF nodeless
  path; per-segment tagged quad sectors each carrying their own
  Sector_Set3dFloor control sector measured back at exactly the
  described heights, nine per arc in one load.

## InputProcess + injected input, measured (GameBuilder VERB-00, 2026-08-01, 4.14.3)

The playbook's input facts said reading cmd.buttons works, injection is
dead, and `InputProcess` was untested. Measured with a marker-pattern
probe (tools/input_probe.py; logs/verb00-input-*.txt):

- **`StaticEventHandler.InputProcess(InputEvent e)` WORKS** and sees
  raw input BEFORE bindings: keyboard KeyDown/KeyUp with DIK scancodes
  (number row 1..6 = 0x02..0x07), mouse buttons as scans 0x100+, and
  the MOUSE WHEEL as KeyDown *and* KeyUp pairs of 0x198/0x199 per
  notch. No IsUiProcessor needed (that gates UiProcess only).
- **`return true` genuinely consumes** — proven observably, not by
  reading the code: with the probe consuming mouse1, a real click was
  logged by InputProcess yet never produced a cmd.buttons edge; with
  consumption off, the same click set BT_ATTACK. Consume the KeyUp
  half too or half-pairs leak.
- InputProcess is **ui scope**: it cannot touch play state. The
  `EventHandler.SendNetworkEvent -> NetworkProcess` bridge works from
  inside it (measured round trip) — verb switching rides on it.
- **OS-level SendInput reaches the engine** when its window is
  foreground: keyboard via KEYEVENTF_SCANCODE, wheel via
  MOUSEEVENTF_WHEEL, and mouse buttons — all arrived in InputProcess
  AND (unconsumed) in cmd.buttons. This REFINES the earlier "SendKeys
  never reaches the engine / no input injection exists" lessons: menu
  navigation by synthetic keys remains dead (keys rain into the sim,
  as measured before), but the SIM-side input path IS injectable. So
  the physical click/keypress is now testable headlessly on an IDLE
  desktop (front the window first; a human's real input mixes in and
  contaminates aims). GameBuilder's tests/test_verbs_e2e.py carries
  the pattern (real key -> verb switch, real wheel -> adjust, real
  click -> command marker).
- Cell-solidity is measurable from the live level with no doc access:
  solid grid cells compile to VOID, so
  `IsPointInLevel((cellcenter, floorZ_of_PointInSector + 1))` is true
  exactly for open cells — used to tell "ray entered a wall" from
  "ray left through a ceiling" when deriving edge-target payloads.

## Sky, and "a sector record is not occupied space" (GameBuilder EVID-01, 2026-08-01, 4.14.3)

Two facts from the scale-proof map (a 48x44 outdoor level loaded over
a real DOOM II).

**Sky is a FLAT NAME, and it comes from the base game.** A sector is
outdoors when its ceiling flat is literally `F_SKY1` — no MAPINFO
`sky1` line, no special linedef, no per-map setup. Measured over
DOOM II: `TexMan.CheckForTexture("F_SKY1", TexMan.Type_Flat)`
resolves, `TexMan.GetName(sec.GetTexture(Sector.ceiling))` reads back
`F_SKY1`, and the engine draws sky there. A map lump can even be
declared with a bare `map GBMAP04 "..." {}` in an add-on MAPINFO and
still get the base game's sky. Corollary already in section 5: a
STANDALONE with no `F_SKY1` logs the benign "Unknown texture: F_SKY1"
instead — so an outdoor level is a base-game-backed thing, and the
add-on-over-IWAD path is where outdoors actually works. A generator
that passes ceiling-texture names straight through needs no sky
feature at all; it needs the base game mounted.

**A sector that carries a 3D floor is not proof that the sector owns
any ground.** Measured the hard way: nine per-segment quad sectors all
appeared in `Level.Sectors` with their 3D floors attached at exactly
the described heights, and four of them occupied no space at all —
`Level.PointInSector` at those segments' centroids returned the
SURROUNDING room, with zero 3D floors. Cause: the quads' boundary
linedefs were wound with the quad on the BACK side while the
inter-quad lines put it on the FRONT, so the outline disagreed with
itself and the node builder did not give the region to the sector that
was tagged for it. Swapping `sidefront`/`sideback` on exactly the
boundary lines fixed it, measured 0/4 -> 4/4.

The harness lesson generalizes past this bug: **enumerating sector
records is a weak geometry check.** Ask the engine which sector owns a
POINT INSIDE the shape (`Level.PointInSector(centroid).Index()` plus
`Get3DFloorCount()`), and for solid volumes ask
`Level.IsPointInLevel` inside the body and just outside it. A gate
built only on "do these sectors carry these slabs" passed a parapet
that was missing four of its nine segments for a full day.

Probe-point gotcha worth its own line: `PointInSector` on an exact
sector boundary is ambiguous. Derived segment fans put VERTICES at
segment joins, so probe at a segment MIDPOINT/centroid, never at the
join — the first run of this probe blamed the geometry for what was,
that time, a badly chosen sample point.
## Winding disagreement is orientation-independent (GameBuilder FMT-02e, 2026-08-01, 4.14.3)

Follow-up to the section above, and a correction to how its last
paragraph reads as a recipe. "Swapping `sidefront`/`sideback` on the
boundary lines fixed it" was true of that one shape and is NOT the
general fix. Measured on the same generator, same engine, with the arc
mirrored so its fan winds the other way:

  * fan wound CLOCKWISE  -> 20 of 20 boundary edges on the wrong side,
                            0 of 8 inter-segment edges;
  * fan wound COUNTER-CW -> 0 of 20 boundary edges, 8 of 8 inter-segment
                            edges.

Two families of linedefs bound the same region, each hand-assigned in
its own place, and they disagreed. Whichever way the region happened to
wind, exactly one family was wrong — so a fix that swaps a named family
just moves the breakage to the mirrored shape. The durable fix is to
DERIVE each linedef's front/back from where the region actually lies
(sign of the cross product of `v2-v1` against a point inside it; front
is the RIGHT side) in one place that every edge goes through, and to
refuse loudly if a two-sided edge's two regions do not land on opposite
sides.

Two probe facts from the same run, both cheap and both worth keeping:

  * **Occupancy can be PARTIAL.** The broken parapet was present for
    segments 0–4 and absent for 5–8: the node builder resolved half the
    outline and gave up on the rest. A single probe point inside "the
    shape" is a spot check that can land in the good half. Probe EVERY
    segment.
  * **Occupancy responds to winding in both directions**, which makes a
    strong two-sided harness: on geometry that measures 4/4 present,
    re-swapping the boundary lines in the emitted TEXTMAP takes it to
    0/4. Breaking something that works, on purpose, proves the probe is
    measuring the thing you think it is — the same trick that proved
    the diagnosis originally, run in reverse.
- **Converting another engine's HD pack: read its own TEXTURES/SNDINFO
  as the join, and copy view-weapon geometry VERBATIM.** An ECWolf
  pack maps its art onto engine sprite names in its own lumps
  (`Sprite PISGA0 { Offset -95,-55 Patch V_LUGR_A }`), including which
  painted image each of the five view frames uses and the per-frame
  offsets that animate recoil - authored data that beats any filename
  guess. ECWolf's view-sprite placement matches this engine's, so
  copying size/scale/offset unchanged (renaming only the sprite) lands
  each weapon exactly where its author intended. Deriving placement
  instead - fitting their art onto our sprite's bounding box - drew a
  pistol three times too big, because their art is cropped at the
  canvas edge while ours floats inside a larger frame. Same principle
  for sounds: their SNDINFO names which wav plays each logical event,
  and lines its author left COMMENTED OUT (a whole set of remastered
  enemy voices) stay off on our side too.
- **Image-verifying sprite mappings: composite alpha onto one fixed
  backdrop and crop to the art's bbox before comparing.** `.convert(
  "RGB")` on a palette sprite fills transparent pixels with whatever
  color sits at that index, so a ~95%-empty sprite gets compared on
  its background - our knife lost its argmin to a Pac-Man ghost
  easter egg. And raw canvases compare PLACEMENT, not art, when the
  two packs frame on different canvas sizes. A weapon's five frames
  must also count as interchangeable answers: HD idle art can resemble
  our recoil frame more than our idle frame, which says nothing about
  whether the right weapon was picked.
- **In-engine screenshots beat OS screen grabs for verification.** A
  `screenshot <name>` in an exec cfg captures the engine's own
  framebuffer; an OS grab catches whatever window is in front (a stray
  tool window blanked one run) and needs `SetProcessDPIAware()` to
  avoid cropping on a scaled desktop. Two traps: each LINE of an
  exec'd cfg is its own command buffer, so `wait` on its own line does
  NOT hold back the lines below it (quit raced ahead of the shot -
  use one semicolon chain on one line); and an explicitly named shot
  ignores `screenshot_dir` and lands in the working directory.

## Where the engine window is born (GameBuilder WIN-00, 2026-08-01, 4.14.3)

Every blink-reload is a new PROCESS, so it is a new WINDOW - the user
re-drags and re-sizes it every few seconds unless the launcher decides
where it opens. Four boots, each reading the real rect back with
`GetWindowRect` (tools/window_probe.py; `logs/win00-window-probe-*.txt`),
settled which channels place it. Measured on a 1920x1080 work area:

- **`-width` / `-height` DO NOT SIZE THE WINDOW.** They set
  `vid_defwidth` / `vid_defheight`. With `-width 960 -height 600` and
  nothing else the window is born **1536x864 at 192,108** - 80% of the
  desktop, centred, i.e. the engine's own default. Any launcher that
  believes `-width` controls the window is measuring nothing.
- **Every launch creates a fixed stub window FIRST - 640x480 at
  640,300 - then resizes ONCE to the final rect. The baseline does it
  too.** So "born correct" is not literally reachable through any
  channel, and a probe that samples too slowly reports a comforting
  single rect and lets you believe it is: the first run of this probe
  did exactly that on all four arms at 50 ms sampling. Sample as fast
  as the loop allows and TIMESTAMP every distinct rect. The honest
  question is not "was the FIRST rect right" but "once the engine has
  sized the window, does it ever sit at any OTHER rect" - one settle
  straight to the requested rect is the same single move the untouched
  default path makes, just to the right place. (Both stages landed
  inside the same millisecond sample here, so the stub is not
  something a user sees; it is something a claim has to account for.)
- **`+set win_x / win_y / win_w / win_h / win_maximized` WORKS, and it
  IS that single settle** - stub, then straight to the requested rect,
  then nothing for the rest of the window's life. These are archived
  GLOBAL cvars (they live in `[GlobalSettings]`, not the game's own
  section) that video init reads. `win_maximized 1` is honoured too
  (`GetWindowPlacement` reports SW_SHOWMAXIMIZED), at the cost of one
  extra stage: stub -> the win_w/win_h rect -> maximized.
  **This does NOT contradict the launch-line `+bind` lesson - it bounds
  it.** `+bind` loses because binding init runs AFTER the `+command`
  batch and overwrites it; video init runs after `+set` and READS it.
  "+commands run early" still does not mean "+commands win": which
  wins is per-subsystem and has to be measured one subsystem at a time.
  `win_x/win_y` are the WINDOW rect (outer, including frame), not the
  client area: ask for 880x560 and `GetWindowRect` returns 880x560.
- **A seeded config works too, and a partial `[GlobalSettings]` is
  SAFE** - unlike `[<Config>.Bindings]`. Writing a config containing
  nothing but `[GlobalSettings]` + the four `win_*` keys boots clean,
  loads the map, and the editor-binds gate stays green (plain cvars
  absent from the file keep their compiled-in defaults; only the
  bindings reader treats "section present" as "defaults suppressed").
  Useful when a config must carry the placement, but `+set` is the
  simpler channel and needs no file.
- **`SetWindowPos` with `SWP_NOACTIVATE | SWP_NOZORDER` is the
  complement, and measurably does not move the foreground** - the
  window jumps, focus does not. Use it only for what the creation
  channel cannot cover (an engine-clamped rect, a remembered rect from
  a monitor layout that no longer exists). It is a SECOND settle by
  construction, so it is the fallback, never the primary.
- Reads and writes both need `SetProcessDpiAwareness` first (Eric's
  desktop is 125%) - the same lesson as the screenshot protocol, other
  direction: an unaware process is fed virtualized coordinates and
  lands the window wrong as well as measuring it wrong.

**Focus across a blink, measured (`logs/harn10-focus-*.txt`):** with
the engine window genuinely in the foreground, the window that comes
back after the relaunch HOLDS the foreground - 4 of 4 measurable
rounds. So the user keeps building without re-clicking, and that is
inherent to the relaunch, not something the launcher does. Two
measurement traps worth keeping: (1) `SetForegroundWindow` from a
BACKGROUND process is a no-op, so a harness that just calls it and
proceeds is measuring a state it never established - borrow the
foreground thread's input queue (`AttachThreadInput`) and then VERIFY
the window is actually in front, or honestly skip the round; (2) on a
live desktop the user's own window steals the foreground mid-run (it
did, once in three rounds) - report those rounds as unmeasured rather
than as failures.

Cost of all of the above on the blink: **none measurable.** Interleaved
arms, four blinks each, same level and engine: 2.602 s mean before,
2.598 s after (`logs/harn10-timing-*.txt`). The capture is one
`EnumWindows` on a window that already exists, and the placement rides
on the launch line that was being built anyway.
- **Joining two engines' asset sets: use each side's OWN authored
  tables, never filename arithmetic.** ECWolf names enemy sprites by
  ROLE with letters its authors chose (GARD A stand, B-E walk, F-H
  attack, I-J pain, K-N death); we name them by role too but split
  across four sprite names (GRDS/GRDW/GRDA/GRDP/GRDD). Neither side
  follows VSWAP order, so nothing relates the letters. Both DO publish
  their role tables - theirs in DECORATE state blocks, ours in the
  generated tables from WL_ACT2.C - so the join is state label to
  state label (Spawn/Path/Missile/Pain/Death), taking each side's
  DISTINCT poses in order of first appearance because both replay
  poses within a state (our SS has nine SHOOT rows drawn from three
  sprites). Same for sounds: match the actor, not the filename - our
  Gretel's sight sound is whatever THEIR Gretel's seesound resolves to.
- **Two games that both number from zero need two addon packs.**
  Wolf3D tile 50 is a door at WALL098; Spear overrides tile 50 with
  cobblestone, which is also WALL098 in its own build. One shared pack
  would paint Spear's cobblestone onto Wolf3D's doors. Split the pack
  per game and have the launcher pass which game it is starting.
- **Sprite rot 0 and rots 1-8 cannot coexist for one frame.** When the
  HD pack has a single unrotated image and our sprite is rotated
  (a pain pose the original drew once), write that one image to all
  eight of ours. In the reverse case take their ROTATION 1 only -
  writing each of their rotations onto our single rot-0 lump leaves
  whichever came last, which pointed the rocket away from the player.
- **Audio cannot be verified the way art can, and must not be matched
  by signal at all.** A remaster REPLACES recordings rather than
  cleaning them up - a two-second MP40 burst stands in for a
  half-second sample - so duration and loudness envelope prove nothing;
  using them as a gate rejected two thirds of a correct map, and using
  them to DISCOVER pairings confidently matched the machine gun to
  BJ's grunt. Derive sound maps from role, and say plainly that they
  rest on that alone.
- **Image checks should be two-tier once the joins are authored.** A
  systematic slip (the off-by-one class) lands the argmin on a
  near-exact match; a repaint that merely drifted lands it in the same
  neighbourhood as the intended lump. Withhold at the first, warn and
  ship at the second - a single strict threshold threw away correct
  art (a remastered pot really does look like a different pot). Also
  treat known-equivalent groups as agreement: a wall's light/dark
  sibling face, a weapon's five view frames, an enemy's poses.

**Window geometry does NOT move where a view-ray aim lands** (same
session, `logs/harn10-aim-*.txt`). Worth measuring rather than
assuming, because window size genuinely changes aspect and FOV and it
is easy to argue yourself into either answer. Four engine lives at
1536x864, 640x480, 700x900 and 1400x520, same map, same spawn pose:
the engine's own aim markers report the identical target cell and the
identical wall cell in all four. A ZScript fixed-step view-ray march
is a function of the player's position/angle/pitch, so screen shape
never enters it. Practical consequence for harnesses: cell assertions
in aim e2e tests are safe across window changes - when one of them
fails, suspect the human at the desk (a mouse over the test engine's
window steers the aim, and that shows up as MORE THAN ONE distinct aim
within a single run) before suspecting the geometry.

## 3D model support in the pinned build (measured 2026-08-01, 4.14.3)

Confirmed by string-probing `uzdoom.exe` itself (not recalled from
GZDoom docs — the prime directive applies to capability claims too):

- `MODELDEF` present — the lump that binds models to actor states.
- `IDP2` / `IDP3` present — MD2 and MD3 magic numbers, so the classic
  Quake model formats load.
- `INTERQUAKEMODEL` / `IQM` present — **skeletal animation** is
  available; this is what modern mods with real animated 3D characters
  use, and it is the format to target for new work.
- `A_ChangeModel` and `SetAnimation` present — runtime model swapping
  and animation control from ZScript.
- `VOXELDEF` present (already known; KVX remains the voxel route).

Caveats that do NOT change with models: actor collision is still the
cylinder (radius + height) — a mesh never drives collision. Art cost
moves entirely to modeling/rigging. Mixing models with sprites reads
badly; mods that use models generally commit fully.

Portfolio relevance: the voxel stack (CCFPS voxelize + WolfDoom KVX
writer) is the sibling branch of the same import road; GameBuilder's
blueprint road-marks sprite/voxel import with verdict-card sizing, and
models slot into that same flow rather than needing a new concept.

## Where the engine keeps its things table (GameBuilder THINGS-01, measured 2026-08-02, 4.14.3)

Every fact a level editor needs about stock Doom things is machine-readable
inside `uzdoom.pk3`. Read it; do not recall it.

- **Editor numbers**: `mapinfo/doomitems.txt`, a `DoomEdNums { 3001 =
  DoomImp ... }` block (294 numbers in 4.14.3, including port extensions).
  This is the engine's own map-number → actor-class table.
- **Footprints**: `zscript/actors/doom/*.zs`, `Default { Radius; Height; }`,
  resolved up the inheritance chain. The base `Actor` default is
  **Radius 20 / Height 16** (`zscript/actors/actor.zs`), which is what every
  pickup inherits.
- **Collision is the cylinder**, so radius/height is exactly what an editor's
  footprint ghost must draw.

**`Skip_Super` is the trap.** A class whose `Default` block contains
`Skip_Super;` does NOT inherit its parent's properties — everything resets to
`Actor`'s defaults. Doom's placeable corpses (`DeadZombieMan`, `DeadDoomImp`,
`DeadDemon`, …) all use it, so a corpse is **20/16**, not the 20/56 of the live
monster it inherits from. Walking the inheritance chain naively gives every
corpse a 56-unit-tall footprint that the engine does not agree with. Same for
flags: `Skip_Super` / `ClearFlags` drop `+SOLID`, which is why the corpses and
the `Nonsolid*` gore variants are walk-through while their siblings block.

**Sprite lumps must be SCANNED, never constructed.** A frame can live in a
6-char lump (`TROOA1`) or a mirrored 8-char one (`SPIDA1D1` — one lump serving
rotations 1 and 4), and different IWADs pack the same frame differently:
measured 2026-08-02, id's DOOM2.WAD ships `BOS2A1C1` where Freedoom Phase 2
ships `BOS2A1`. Build an index of the lumps between `S_START`/`S_END` and match
prefix+frame against it, preferring rotation 1 (front view), then 0
(rotationless), then the lowest rotation present, for a deterministic pick.

**Doom II's roster really is absent from Doom 1 data**, measured across all four
IWADs (DOOM.WAD, DOOM2.WAD, freedoom1.wad, freedoom2.wad): CPOS, BOS2, VILE,
SKEL, FATT, BSPI, PAIN, SSWV, KEEN, BBRN, SGN2, MEGA, TLMP, TLP2, HDB1-6, POB1,
POB2, BRS1 exist only in the Doom II pair. Freedoom's coverage matches its
commercial counterpart exactly — 91 things for doom1 content, 114 for doom2 —
so a per-content availability flag is honest for both. Two quirks worth
remembering: `PIST` (a pistol pickup sprite) exists in BOTH Freedooms and in
NEITHER commercial WAD, and `BON3`/`BON4` (the beta score items ZDoom still
carries editor numbers for) exist in none of the four.

## The level exit is a LINE special, not a thing (GameBuilder THINGS-04, measured 2026-08-02, 4.14.3)

Measured in the engine's own vanilla→ZDoom translation table,
`xlat/base.txt` (linedef section):

```
 11 = USE,   Exit_Normal (0)      51 = USE,   Exit_Secret (0)
 52 = WALK,  Exit_Normal (0)     124 = WALK,  Exit_Secret (0)
197 = SHOOT, Exit_Normal (0)     198 = SHOOT, Exit_Secret (0)
```

So an exit is a **linedef carrying an action special**, triggered by use
(switch), walk-over, or gunshot. Nothing in `DoomEdNums` maps to an exit actor,
and the engine's own repair code reaches for lines, not things
(`zscript/level_compatibility.zs`: `SetLineSpecial(1970, Exit_Normal, 0)`).

The one thing-shaped level-end in stock Doom is the **Icon of Sin**: killing
`BossBrain` (editor number 88) runs `A_BrainDie` in its Death state, which ends
the map. It is a boss script, not a placeable exit — and it only behaves as one
alongside `BossEye` (89) and `BossTarget` (87) in a purpose-built room.

Not measured here, and worth measuring before it is trusted: the numeric UDMF
`special` id for `Exit_Normal` (the xlat table names the constant, and the
constant is defined engine-side in C++, not in the pk3). Emit and boot one map
to confirm, or drive the exit through a named special in the compiler.

## Repainting a LIVE map, and why a generator still cannot (GameBuilder V4, 2026-08-02, 4.14.3)

Asked because an approved design page promised that painting a texture
would apply instantly, with none of the ~3 s rebuild every other edit
costs. Measured with a four-boot probe (`tools/paint_probe.py`;
`logs/paint-probe-*.txt`), both halves read back from the engine itself:

- **Changing a texture on a running map WORKS.** `Sector.SetTexture(
  Sector.floor, tex)` and `Side.SetTexture(Side.mid, tex)` both take
  effect immediately (`TexMan.CheckForTexture` to resolve, then
  `TexMan.GetName(sec.GetTexture(...))` reads the new value back).
  Both are `play` scope; no reload, no map restart.
- **And it is still a LIE for any generator that MERGES cells.** The
  smallest surface the engine can repaint is one sector and one
  sidedef — and a compiler that greedily merges equal cells into
  rectangles and collinear boundaries into runs makes both of those
  much bigger than the cell the user aimed at. Measured on a 16x8 test
  level: the aimed cell's sector also covered two other probe cells,
  and its "wall" was ONE 352-unit linedef spanning **11 cell widths**.
  Painting live therefore repainted eleven cells of wall and a whole
  room's floor; compiling the equivalent one-cell description edit
  repainted one cell and split the run into three. Live and compiled
  disagreed on 3 of 7 probe surfaces.
- The control in the same probe is what makes that a measurement
  rather than a preference: a cell deliberately built ALONE in its own
  sector behind a one-cell wall run agreed on all 7 surfaces. So the
  probe can report agreement; it reported disagreement for the merged
  case because the merged case disagrees.
- Splitting a sector or a linedef at runtime is not available — a
  running map cannot grow geometry — so there is no way to narrow the
  live change to match the compiled one. **Instant paint is available
  only to a generator that emits one sector and one sidedef per cell,
  and that trade (no merging) is far more expensive than the blink.**
- Generalization worth keeping: *"can the engine change X live?" and
  "will changing X live show what the next build produces?" are two
  different questions, and only the second one decides whether the
  feature can be sold as instant.*

## Negative cvar values are silently DROPPED by `+set` on the launch line (GameBuilder, 2026-08-02, 4.14.3)

Found because two aim-parity poses asking for a NEGATIVE view pitch
came back as pitch 0 while every positive pitch restored exactly.
Measured directly (`tools/cvar_sign_probe.py`) by setting cvars on the
launch line and reading them back from inside the loaded map:

    +set gb_spawn_pitch  -40.0  -> engine holds   0.0   LOST
    +set gb_spawn_angle   40.0  -> engine holds  40.0   OK
    +set gb_spawn_x      -64.0  -> engine holds   0.0   LOST
    +set gb_floor_min      -96  -> engine holds -128.0  LOST (default)

- **Cause:** `["+set", name, value]` puts the value in its own argv
  slot, and a token beginning with `-` is how the engine's command-line
  parser marks the start of a new PARAMETER. The `+set` command is cut
  off before its argument and does nothing. Positive values are
  unaffected, which is exactly why this hides: every launcher that
  passes only positive cvars looks correct forever.
- **Fix, same channel, no new mechanism:** emit the whole command as
  ONE argv token — `"+set gb_spawn_pitch -40.0"`. Inside a console
  command line the minus is just a number. Proven from both sides on
  the same cvars minutes apart: LOST before, OK after.
- **What it had been costing, invisibly:** the blink-reload restores
  x/y/z/angle/pitch, and pitch is the one that can be negative — so
  every rebuild while the user was LOOKING UP silently levelled their
  view, and the "restore is EXACT" measurement had only ever been taken
  with a non-negative pitch. A guard cvar (`gb_floor_min -128`) was
  also never actually being forced; it went unnoticed because the value
  it failed to set equalled the compiled-in default.
- Lesson, adjacent to the `+bind`-is-inert entry: *a launch-line
  channel that works for the values you happened to try is not a
  channel that works. Probe the boundary values — signs, zero, empty —
  by reading them back from inside the engine.*

## `IsPointInLevel` false means TWO different things (GameBuilder V4, 2026-08-02, 4.14.3)

Refinement of the aim-march entry above, surfaced when the aim payload
grew a FACE identity (which surface, not just which cell). A fixed-step
march breaks when `Level.IsPointInLevel(p)` goes false — and that is
true both when the ray entered a WALL and when it left the room through
a ceiling or below a floor. A payload that only names a cell cannot
tell the difference and does not care; a payload that names the SURFACE
must, or every upward aim reports the wrong face. Distinguish with the
cell-solidity probe already in use (`IsPointInLevel(cellcentre,
floorZ+1)`): solid neighbour = a wall face, otherwise read
`sector.ceilingplane.ZatPoint` at the breaking sample and answer
ceiling-vs-floor. A Python mirror that tests openness in 2D never takes
the wall branch at all, so the two implementations silently disagree
there until a parity pose actually looks up.
## The exit's NUMBER, and the field next to it that nobody writes (GameBuilder THINGS-04 follow-up, measured 2026-08-02, 4.14.3)

The section above ("The level exit is a LINE special, not a thing")
closed with one fact left honestly unmeasured: the numeric UDMF
`special` that fires `Exit_Normal`. Measured now, seven engine boots,
`F:/GameBuilder/tools/exit_probe.py`
(`logs/exit-probe-20260802-074228.txt`, one `logs/harn03-exit-*.log`
per boot, zero script errors throughout).

**Exit_Normal = 243, Exit_Secret = 244**, `arg0 = 0`, as the UDMF
`special` field in the `zdoom` namespace.

- **The engine can be asked for a line special's number directly.** The
  ZScript compiler resolves a line-special NAME to its C++ number - that
  is how `zscript/level_compatibility.zs` writes
  `SetLineSpecial(1970, Exit_Normal, 0)` with no constant defined
  anywhere in the pk3. So `Console.PrintfEx(PRINT_LOG, "%d",
  Exit_Normal)` makes the engine print the number itself. This
  generalizes: **any line special's id is readable from inside a running
  map by naming it**, which beats a wiki table and beats grepping the
  package (the numbers are not in the package at all).
- **The number alone does nothing. Activation is a SECOND, mandatory
  UDMF field.** A linedef carrying `special = 243; arg0 = 0;` and no
  activation flag was walked over repeatedly with the level never
  ending. `playercross = true` reads back from the engine as
  `line.activation = 1` (`SPAC_Cross`); `playeruse = true` reads back as
  `2` (`SPAC_Use`) and then REFUSES the walk-over while firing on use.
  This is the trap for any generator whose only prior experience of
  `special` is `Sector_Set3dFloor` (160), which needs no activation and
  therefore never taught the emitter to write one - GameBuilder's
  compiler emits `special/arg0..arg3` and nothing else, so its first
  exit line would have been silently inert.
- **The vanilla numbers are a namespace trap, and they fail QUIETLY.**
  `xlat/base.txt`'s `11/51/52/124/197/198` are `doom`-namespace line
  TYPES; the translator does not run for a map that says
  `namespace = "zdoom"`. Measured: `special = 52` (vanilla WALK
  Exit_Normal) with `playercross = true` in a zdoom-namespace map is not
  an exit - no error, no warning, the player just walks through.
- **Tell the two exits apart by DESTINATION, not by name.** Give the map
  a `next` and a different `secretnext` in MAPINFO; 243 goes to `next`,
  244 to `secretnext`. Reading a name back proves nothing; the engine
  going somewhere different does.
- Walk-over exits are **not side-restricted by default**: the firing
  crossing came from the linedef's BACK side of a two-sided line whose
  `line.flags` read back as `4` (ML_TWOSIDED only, no
  ML_FIRSTSIDEONLY).
- Activation timing detail worth knowing when a harness asserts tics:
  the special fires on the move that would put the player's CENTRE on
  the line, and the level teardown happens before that tic's
  `WorldTick` - so the last position sample is one step SHORT of the
  line (184 with the line at 192, 8 units per tic) and `WorldUnloaded`
  reports the tic before the crossing sample the control run logs. An
  exit truncates its own position track; a validity check that demands
  a sample past the line marks every working exit "unmeasured".

**How to see an exit fire, unattended.** The old note in section 5 ("a
successful level exit is INVISIBLE in the logfile") is now solved, not
worked around: `StaticEventHandler.WorldUnloaded(WorldEvent e)` fires at
the exit and `e.NextMap` carries where the engine is going, and a
second `WorldLoaded` for a different `Level.MapName` corroborates it.
Add `nointermission` to the map in an add-on MAPINFO or the stat screen
waits for a keypress nothing can press. Two log-shaped gotchas cost a
run each here: the corroborating marker needs ~2-8 s of extra polling
(killing the engine 1.5 s after the unload loses it every time), and a
marker regex written `next=(\S+) secretnext=(\S+)` silently drops the
destination map's own line because ITS `secretnext` is empty - `\S*`.

**Driving a player across a line on a desktop someone is using.** No
input injection is needed and none should be used: set
`players[0].mo.vel` to an absolute WORLD-space vector from `WorldTick`.
A human turning the view cannot steer it (the drive is not
forward-relative), and the engine's own `TryMove` path - the one a real
player takes - collects and activates the crossed line specials. The
run then proves its own validity from the position track: a control
that reports "no exit" only counts if the same track shows the player
reaching the line.

Small pipeline lesson from the same session: **`version "4.14"` at the
top of an `#include`d ZScript file is a parse error** ("Unexpected
'version'"). The version line belongs in `zscript.txt` only. Symptom is
the section-7 one - the log stops at `LoadActors` and one
`Script error` line names the file.

---

## Placed things: skill filtering, ambush, and asking what actually spawned (GameBuilder V5, measured 2026-08-02, 4.14.3)

**UDMF skill flags are honoured at SPAWN, and the compiler that omits
them makes things vanish on Ultra-Violence.** A `thing { ... }` block
carries `skill1`..`skill5` booleans; the engine filters as it spawns, so
the map file can be perfectly correct and the actor still not exist.
Measured with three monsters in one map, one boot: all-skills present,
easy-only absent, hard-only absent (the engine ran at Hurt Me Plenty).
The trap worth naming: a generator that emits only `skill1 = true;
skill2 = true; skill3 = true;` — which is a natural-looking three-line
default — puts NOTHING on Ultra-Violence or Nightmare. The Doom
grouping is easy = skill1+skill2, medium = skill3, hard = skill4+skill5.

**`ambush = true;` in UDMF lands on the actor as `bAMBUSH`**, readable
from ZScript (`a.bAMBUSH`), so the deaf flag is verifiable from inside
the running game rather than from the file.

**Ask the engine what spawned, not the map what was written.** A
`ThinkerIterator.Create("Actor")` sweep printing class, position, angle
and flags is the honest gate for any placement feature — the file says
what the compiler wrote, and everything interesting (skill filtering,
spawn failure, an actor pushed out of a wall) happens after that.
Two filters keep the output readable and honest: skip `PlayerPawn`, and
skip `Inventory` whose `owner` is non-null (carried inventory is an
Actor too and all of it sits at (0,0,0) inside its owner).

**`out` is a ZScript KEYWORD.** `String out = "";` is a load-time parse
error — "Unexpected 'out'", expecting `';'`. Symptom is the section-7
one: the log stops at `LoadActors` and the `Script error` lines name the
file and every line that touches the variable. Same family as the
`version "4.14"` lesson: cheap to hit, invisible until the engine
refuses to load.

**The clearscope rule, earned a third time.** `RenderOverlay` is ui
scope. A private helper that resolves a selection — even one that only
reads generated `static` data — is play scope unless declared
`clearscope static`, and calling it from `RenderOverlay` is a LOAD-TIME
script error ("Can't call play function X from ui context"), followed by
a cascade of "Unknown identifier" lines for whatever it assigned to.
The rule is now three-for-three: HUD code touching any helper needs that
helper `clearscope static`.

**Adjacent, and not an engine fact but it cost a run:** a `file:///…`
`<img>` does NOT decode in a pywebview/WebView2 frontend loaded from
`file://` — 14 of 14 images rendered and 0 of 14 loaded, measured. Local
pictures have to travel to such a page as `data:` URIs.

## Driving the SKILL from outside, and what that exposes (GameBuilder JDG-16, measured 2026-08-02, 4.14.3)

Follow-on to the skill-filtering section above; four facts, all measured
on the same three-boot run.

**`+set skill N` before `+map` works, and N is ZERO-BASED over the base
game's own skill list.** Over DOOM II that makes 3 = Ultra-Violence
(UDMF `skill4`) and 4 = Nightmare (`skill5`). This is the one channel
needed to test difficulty filtering from a harness — no menu, no
`-skill` argv slot, no config surgery. Same launch-order reasoning as
the window cvars: the `+set` batch runs before the map is started.

**Which skills EXIST is the base game's MAPINFO, not the engine's.** A
standalone shell that says `clearskills` and defines one skill at
`SpawnFilter = 1` has no Ultra-Violence at all, so a thing flagged
`skill1..skill3` looks fine there forever. The same package over a real
IWAD gets that IWAD's five skills and the same thing disappears. Worth
holding onto as a general shape: **a standalone's reduced furniture can
hide a defect that only the real base game can show**, so any check
about difficulty, episodes or player classes has to run over the IWAD
the user will actually use.

**Player starts are NOT skill-filtered by default.** Their `skill*`
flags are ignored unless the map opts in (`filterstarts`), so a
generator emitting `skill1..skill3` for everything makes monsters, items
and decor vanish on UV/NM but still lets the player enter the level.
Measured by restoring the broken emission deliberately: the flagless
monster was gone at Ultra-Violence, the player spawned normally.

**An actor's class name can be spelled differently by the engine's
source and by the running engine.** `GetClassName()` returned
`Zombieman` where `zscript/actors/doom/possessed.zs` declares
`ZombieMan`. ZScript identifiers are case-insensitive, so both are
"right" and neither is wrong — but any harness comparing a name
harvested from the source against a name printed by the running game
must compare case-INSENSITIVELY, or it will report a thing as missing
while its own log lists it standing in the correct place.

## Freezing the world for an EDITOR, and letting the builder walk through it (GameBuilder FREEZE-01, measured 2026-08-02, 4.14.3)

Eric, hands-on with the level builder: *"when I place a monster, it
immediately starts attacking and doesn't stay put."* An editor's world
is a model, not a game -- and the engine already has exactly the right
mechanism, in the last place you would look for an editor feature.

- **`Level.SetFrozen(true)` + `players[0].timefreezer |= 1` is the whole
  recipe.** The freeze stops every thinker; the `timefreezer` MASK is
  what the TimeFreezer powerup sets so its owner keeps moving through
  it (`zscript/actors/inventory/powerups.zs`, `freezemask = 1 <<
  PlayerNumber()`). Set the mask for player 0 and the result is precisely
  an editor: the builder walks, looks, aims and clicks while nothing
  else in the world does anything. `timefreezer` is a plain
  `native int` on PlayerInfo (`player.zs:2902`) and is writable from
  play scope.
- **A StaticEventHandler's `WorldTick` KEEPS RUNNING while the level is
  frozen** -- measured, not assumed, and it is the fact the whole idea
  rests on. The editor's aim march, its particle ghost, its HUD readout
  and its click handling all live in WorldTick, so a freeze that stopped
  it would have frozen the editor instead of the world. Measured over 10
  actor sweeps at 35-tic intervals in a frozen level: markers flowed the
  whole time.
- **Particles keep drawing.** `Level.SpawnParticle` respawned every
  WorldTick still renders under the freeze, so a particle-wireframe
  ghost survives it. (This is consistent with WorldTick running, but it
  is a separate observable and was checked as one.)
- **Apply it on the FIRST TICK, not in `WorldLoaded`.** Map actors run
  `PostBeginPlay` on tick one, after WorldLoaded -- the same ordering
  trap as every other "mutate map-spawned actors" job in this playbook.
- **Re-assert it cheaply rather than trusting one call.** Frozen-ness is
  shared sim state; anything in a base game could in principle change it
  (a TimeFreezer pickup lying in a user's own level would), and a world
  that quietly came back to life mid-build is the defect this fixes.
  Re-checking `Level.isFrozen()` every 10 tics costs nothing.
- **Position is HALF a stillness check; frame is the other half.**
  Measured against the real unfrozen state: an Imp facing away from the
  player never woke and never moved one unit, so a position-only gate
  called the unfrozen world "inert" and would have shipped a freeze that
  did nothing. The engine's own `a.frame` / `a.tics` are what "thinking"
  looks like from outside -- and a monster winding up a melee swing does
  not move at all. Print both. **And face the subject AT the player**:
  monsters only see what is in front of them, so a test monster placed
  facing away is a test that never fires.
- Freezing is a SESSION behaviour and must never become a map property.
  Proven at the artifact level: the packaged `maps/*.wad` lump is
  byte-identical between the frozen editor build and the play-test
  build, and carries the compiler's own TEXTMAP text verbatim.

## No app can drive a BACKGROUND engine window; the foreground round-trip is free (GameBuilder CONN-07, measured 2026-08-02, 4.14.3)

The long-standing note in this project was "there is no live
app-to-engine channel". VERB-00 had already refined the older
"SendKeys never reaches the engine" lesson to *SendInput does reach it
when its window is foreground*. What was never measured is whether a
WINDOW MESSAGE could reach a backgrounded one -- which is what a desktop
app clicking its own panel would need. Measured with two engines, one
holding the foreground while the other is probed
(`GameBuilder/tools/panel_channel_probe.py`), with both controls fired:

- **Every posted-message channel is DEAD.**
  `PostMessage(WM_KEYDOWN/WM_KEYUP)` to the engine's top-level window,
  the same to its child windows, `SendMessageTimeout` of the same, and
  `PostMessage(WM_MOUSEWHEEL)` -- none of them reaches a backgrounded
  engine's `InputProcess`. The engine reads RAW INPUT, which follows the
  foreground window; the legacy message path is not read at all.
- The run proves it was measuring rather than merely silent: the SAME
  keys arrive when the engine is fronted (positive control), and a
  SendInput fired while it was backgrounded landed in the OTHER engine
  that held the foreground (negative control).
- **The FOREGROUND ROUND-TRIP is cheap and, more importantly, INERT.**
  Handing the foreground to the engine, injecting, and taking it back
  measured **63-78 ms**; focus returned to the app window every time;
  and -- the fact that decides whether this is usable at all -- the
  engine's own `GB_POS` markers reported the player's view moved
  **0.000 degrees in angle and 0.000 in pitch**, with the mouse cursor
  at the identical screen pixel afterwards. A focus hop that silently
  spun the builder's aim would have been worse than no channel.
- **Only the process that OWNS the foreground may give it away**, so
  this works from an app the user has just clicked and does NOT work
  from a background harness. Coming back needs `AttachThreadInput` on
  the engine's thread (the HARN-10 focus lesson, other direction). Both
  legs must be VERIFIED by reading `GetForegroundWindow` back: a
  `SetForegroundWindow` that did nothing looks exactly like one that
  worked.
- Consequence for tooling: a desktop app CAN drive a running engine, and
  the honest way to do it is to synthesise the gestures the engine
  already understands rather than to invent a command surface. Plan the
  gestures against what the engine last REPORTED, deliver them, then
  make the ENGINE confirm the new state by marker -- never let the plan
  grade itself. An off-by-one plan selects the neighbouring item, the
  injection reports success, and everything looks fine.
- Self-test shape worth copying: this probe's only real failure mode is
  a FALSE NEGATIVE ("no channel" because the detector went blind), so
  its `--selftest` PLANTS a real delivery for every key it watches and
  fails unless all of them are reported. A self-test that merely
  re-confirms "nothing arrived" proves nothing.

## A frozen level does not age PARTICLES, and that is not the same fact as "particles keep drawing" (GameBuilder FREEZE-02, measured 2026-08-02, 4.14.3)

Direct correction to the FREEZE-01 section above, earned the expensive
way. That section says *"Particles keep drawing. `Level.SpawnParticle`
respawned every WorldTick still renders under the freeze."* Both halves
of that sentence are true and the conclusion drawn from them was wrong.

- **`Level.SetFrozen(true)` stops particles AGEING, while `WorldTick`
  keeps spawning them.** Anything that draws itself by respawning
  short-lived particles every tic therefore ACCUMULATES without limit
  the moment the level is frozen: nothing expires, every tic's drawing
  is added to the pile. Measured on a particle-wireframe editor ghost
  (60 points a tic, `lifetime 2`): unusable within a second, exactly the
  bug the freeze feature shipped with.
- **The fix is one flag: `SPF_NOTIMEFREEZE` (constants.zs, `1 << 5`).**
  It makes a particle age whatever the world's clock is doing -- an
  editor freeze, a TimeFreezer pickup lying in a user's own level, any
  future time effect. Pair it with `SPF_REPLACE` (`1 << 7`) if the
  drawing must never be denied a slot: a full pool then costs the OLDEST
  particle instead of costing this frame's drawing. Measured before and
  after on the same package, same level, same view sweep: broken frozen
  vs. healthy frozen vs. healthy unfrozen, with the last two now
  IDENTICAL (median 502 lit pixels each).
- **There is no way to delete or count particles from ZScript.** Read
  the engine's own surface before designing around one:
  `LevelLocals.SpawnParticle` is a void native (doombase.zs), the flags
  live in constants.zs, and there is no particle list, no handle, no
  clear, and no count anywhere in uzdoom.pk3. Ageing is the ONLY expiry
  there is, which is why the flag -- not "own your visuals properly" --
  is the answer. `VisualThinker` (visualthinker.zs) is the mechanism
  that CAN be enumerated and destroyed, and it can render as a particle
  with no art (`SetParticleType(PT_ROUND)`); it was rejected here only
  because swapping a measured-good look for an unmeasured one while a
  user is blocked is the wrong trade, not because it would not work.
- **Additive particles that stack SATURATE TO WHITE, and that is what a
  leak looks like before it spreads.** With the view held still, every
  generation lands on the same pixels: the area does not change at all,
  the colour does. Measured on one still frame -- healthy 48
  hologram-cyan + 17 white pixels, leaking 0 cyan + 65 white, the same
  65 pixels. A colour-keyed detector that knows only the healthy colour
  reports the smear as "nothing on screen", which is a false clean bill
  in the exact case that matters.
- **What still runs under the freeze, measured directly in the same
  session:** `WorldTick` (so a handler's own tic counter, and everything
  timed by it, is alive -- 40 `GB_POS` samples in 10 s and a 175-tic
  self-releasing latch that fired at tic 211), and the console NOTIFY
  area's message expiry (two self-clicking engine lives differing only
  in the freeze produced identical text-pixel traces, rising and falling
  the same way). So the freeze's blast radius is narrower than "time
  stops": it is the level's thinkers plus particle ageing.

Generalization worth more than the flag: **a feature that changes a
GLOBAL condition owes a check to everything that lives under that
condition.** The gate that shipped this bug proved its own claim
completely -- monsters stop, play-test stays alive, the map file is
untouched -- and never asked whether the editor still worked inside the
world it had just stopped. When the change is to shared state, the
question "what else runs in here?" is part of the gate, not part of the
review.

**Reading the screen as a harness channel, since the engine will not
count for you.** Where a claim is about what the PLAYER SEES and the
engine exposes no count (particles here), an OS-level grab of the
engine's own client rect is a real measurement channel on this stack:
`GetClientRect` + `ClientToScreen` after `SetProcessDpiAwareness`, then
`ImageGrab.grab(bbox=..., all_screens=True)` -- 32 ms a frame, sampled
three times a second for as long as you like. Three rules earned in one
sitting: crop the status bar and your own HUD text OUT (cyan HUD text is
indistinguishable from a cyan hologram), keep an arm in which the thing
you are counting CANNOT be present (play-test draws no ghost -- it
measured 0, which is what makes the other arms' numbers mean anything),
and compare MEDIAN against MEDIAN over time, never a peak against a
median: perspective alone swings an on-screen area by an order of
magnitude while nothing is wrong.

## Keyboard CHORDS in an editor, and what `+attack` is really bound to (GameBuilder VERB-07a, measured 2026-08-02, 4.14.3)

Moving an editor's undo onto Ctrl+Z raises an old question, and the
answer is not what folklore says:

- **On a fresh Config-namespace ini this build binds `+attack` to
  `Mouse1, Axis6Plus` ONLY.** The classic `Ctrl = +attack` is NOT in
  the modern defbinds. Read straight out of the engine at boot with
  `Bindings.GetKeysForCommand("+attack")` + `KeyBindings.NameKeys`,
  which is worth doing on any build that is about to rely on what a
  key means: a Ctrl chord does NOT fire by default here, and a guard
  written against that trap is defence-in-depth, not a bug fix. Say
  which it is; the difference matters when someone later asks what
  the guard is for.
- **`InputProcess` can swallow a MODIFIER whole, and that is the way
  to make a chord safe without touching the user's config.** It sees
  raw input before bindings and `return true` genuinely consumes
  (already in this playbook). Consuming Ctrl outright in editor mode
  costs nothing (no other editor job) and means the chord can never
  reach the binding layer whatever the user has bound there. This is
  strictly better than patching `[<Config>.Bindings]`, which this
  playbook already warns is easy to get catastrophically wrong.
- **Modifier state for a chord must live in `ui` scope.**
  `InputProcess` is a ui hook and cannot read a play-scope field; a
  `ui bool ctrlHeld;` field declared on the same StaticEventHandler
  works, and is where the SHIFT flag for `Ctrl+Shift+Z` has to live
  too. (The play side still needs its own copy if it acts on the
  modifier -- they are two variables by construction, not one.)
- **Gate the chord keys on the modifier, not the other way round.**
  Claiming bare Z/Y in `InputProcess` eats keys a builder may walk
  with; testing `ours = (scan == Z || scan == Y) && ctrlHeld` first
  leaves them alone.
- **A busy/debounce latch will swallow the second half of a probe.**
  An undo that latches the handler makes the immediately following
  redo answer "still building the last change" -- correct behaviour,
  and a measurement that reads as a missing feature. Space chord
  probes past the latch's own self-release (5 s here) or use a fresh
  engine life per chord.

## Asking the engine WHICH ACTOR is under the ray, cheaply (GameBuilder VERB-07, measured 2026-08-02, 4.14.3)

For an editor that must delete what the reticle is on, a full
`LineTrace` against actors is not needed and a per-tic
`ThinkerIterator` is not wanted:

- **Build the actor index ONCE per engine life** (`ThinkerIterator`
  over "Actor", skipping `PlayerPawn` and owned `Inventory`, on tick
  one so map actors have run `PostBeginPlay`). This is only safe when
  the set cannot change inside a life -- in a blink-reload editor
  every edit relaunches, so it cannot. Store the grid cell and the
  radius, nothing else.
- **When a Python mirror must agree with the ZScript about an actor,
  compare only what both sides provably share.** The app knows a
  thing from its description; the engine knows it from the actor it
  spawned. Cell + radius are the same on both sides by construction;
  spawn Z is not (a ceiling-hanger's is not derivable from the
  description without duplicating the compiler). Testing a COLUMN
  (radius in plan, that cell's floor to its ceiling) instead of a
  cylinder makes parity exact and, as a bonus, means nobody has to
  pixel-hunt a 16-unit-tall bonus.
- **A standalone IPK3 shell spawns none of a base game's actors**, so
  any parity arm that needs a real spawned thing has to boot the
  add-on over a real IWAD. Splitting one harness into a shell arm and
  an add-on arm is cheaper than making the shell define stand-ins.
- **Particle colour is per-spawn, so one `Edge()` helper can draw two
  differently-coloured overlays** from one code path (a build ghost in
  hologram cyan, a delete outline in amber) by switching `color1`
  behind a flag. Useful side effect for pixel-counting gates: a
  detector that classifies only cyan-or-blown-white ignores the amber
  entirely, so a second overlay can be added without re-baselining it.

## Ambient input really does steer a test engine, and there are three
## ways to stop it (GameBuilder HARN-17, measured 2026-08-02, 4.14.3)

This playbook has said for months that "a mouse over the test engine's
window steers the aim" and told harnesses to *suspect the human at the
desk* when a cell assertion fails. That was inference from a symptom.
Measured now, eleven independent engine lives, one arm at a time
(`F:/GameBuilder/tools/contamination_probe.py`;
`logs/contamination-2026*.txt`), every number read out of the engine's
own `GB_POS` markers:

| arm | what was done to it | angle swing | distinct ghost cells |
|---|---|---|---|
| control | nothing | **0.000 deg** | 1 |
| mouse, engine FOREGROUND | 42 SendInput moves over 5 s | **336.27 deg** | **20** |
| mouse, engine BACKGROUND | the same 42 moves | **0.000 deg** | 1 |
| focus hop | 6 verified foreground round-trips, no mouse | **0.000 deg** | 1 |
| held W key | one keydown, 5 s, one keyup | 0.000 deg (position **351.98 units**) | 1 |

So: the mechanism is real and it is LARGE; it needs the engine to hold
the foreground (raw input follows it -- the CONN-07 finding, confirmed
from the other side); **CONN-07's deliberate foreground hop contributes
nothing** (0.000 over six hops, matching its original measurement); and
the keyboard is a second, independent path that moves the BODY rather
than the view. Any harness whose assertions depend on a pose is exposed
to both.

**Three isolation channels, measured, and only two of them work.**

- **`use_mouse 0` WORKS and is total.** Same 42 injected moves, angle
  swing **0.000**. It is not a look-scale knob -- with it set, the
  engine's own `InputProcess` logged NO mouse scancodes at all: a wheel
  notch and a left click that both arrive normally (scans 0x198/0x199
  and 0x100, positive control in the same session) produce *nothing*.
  So it is the right switch for a run that wants no mouse, and it is
  **unusable as a global default** for any suite whose tests inject
  wheel or click gestures.
- **`in_mouse 1` DOES NOT WORK** -- 335.04 deg, i.e. no change. It
  selects a mouse BACKEND, not an on/off. Worth recording because the
  name reads like the opposite.
- **`m_yaw 0` + `m_pitch 0`** also gives **0.000**, and unlike
  `use_mouse 0` it leaves the wheel and buttons alive. It zeroes the
  look SCALE only, so `m_forward`/`m_side` mouse movement is untouched.
- **A SEPARATE WINDOWS DESKTOP WORKS.** `CreateDesktopW` +
  `CreateProcessW` with `STARTUPINFOW.lpDesktop = "winsta0\<name>"`:
  the engine boots there, the map loads and `GB_POS` markers flow, ready
  in **2.9 s** -- the same cost as any other boot -- and user input
  physically cannot reach it, because SendInput follows the calling
  thread's desktop. The price is what the harness gives up: the window
  is INVISIBLE to `EnumWindows` from a process on the default desktop
  (measured false), so WIN-01 window placement, any OS-level pixel
  census and CONN-07 injection all stop working unless the harness
  itself switches desktops; `EnumDesktopWindows(hdesk, ...)` does find
  it (13 windows for the pid). **Python trap that produced a false PASS
  on the first run of this arm: `subprocess.STARTUPINFO` has NO
  `lpDesktop` field.** Setting one is a plain Python attribute that
  `CreateProcess` never sees, and the engine quietly launches on the
  normal desktop -- which looks exactly like success. The real struct
  has to go through ctypes.

**The strongest fix is not an input switch at all: re-assert the pose
from `WorldTick`.** A handler that holds `mo.angle` / `mo.pitch` (and
optionally `mo.pos` / `mo.vel`) every tic before anything reads them
makes the aim a function of what the run ASKED for, whatever arrived at
the window -- mouse, keyboard, controller, any future channel. Measured
against the identical 42-move attack: angle swing **0.000**, one ghost
cell, while the engine reported **70 tics** on which it had to correct
the view (worst single tic 15.12 deg of angle, 6.86 of pitch). That
second number is the other half of the value: the lock is also the
DETECTOR, because it knows the pose it asked for and the pose it found.

**Tic ordering, measured, and it differs between angle and position.**
The playbook already says WorldTick runs after PlayerThink has consumed
the tic's cmd. Refined:

  * the mouse's ANGLE change is already applied when WorldTick runs, so
    re-asserting the angle CORRECTS a move that happened (hence 70
    non-zero deltas above);
  * the keyboard's movement is NOT. Setting `mo.vel = (0,0,0)` in
    WorldTick PREVENTS the step -- the pawn never moves at all
    (displacement 0.000 across a 5 s held W key, against **351.19
    units** in the control arm that locked the angle but left position
    free). Excellent for immunity, and it makes a displacement-based
    detector permanently blind: the honest evidence is the VELOCITY the
    lock is about to throw away (measured 0.78 units/tic, 175 tics).

Two control arms are what make any of the above a measurement rather
than a story, and both are cheap: an arm in which nothing is done
(every "0.000" is meaningless without it), and an arm in which the
thing you are suppressing is deliberately NOT suppressed (without
`keys-lock-nopos`, "the player did not move" and "the key never
arrived" are the same observation).

## Unattended FRAME CAPTURE works after all -- the engine will photograph itself (GameBuilder VOXROT, measured 2026-08-02, 4.14.3)

**This CORRECTS section 5**, which says "unattended FRAME CAPTURE does
not [work]" and concludes that OS screen capture is the only route to
pixels and must therefore be treated as attended. That entry measured
`+map X +screenshot +quit`, where every `+` token is its own command
buffer, so console `wait` defers nothing and the shot happens before a
frame is drawn. Put the whole thing in ONE argv token and it works:

    "+wait 175; screenshot F:/path/shot1.png; wait 35; " \
    "screenshot F:/path/shot2.png; wait 14; quit"

- **An ABSOLUTE path as the shot name is honoured** and the file lands
  exactly there -- the older note that "an explicitly named shot ignores
  `screenshot_dir` and lands in the working directory" is true of a bare
  name and is simply sidestepped by naming the full path. `+set
  screenshot_type png`.
- **`screenshot_quiet 1` matters with more than one shot per life**: the
  "Captured ..." console notify line from shot N is still on screen when
  shot N+1 is taken, and it lands in the picture.
- **No foreground, no DPI awareness, no window handling, and no fight
  with whoever is using the desktop.** The frame is the engine's own
  framebuffer, so it is also unaffected by another window covering it.
- **The prize: two engine LIVES at the same pose are BYTE-IDENTICAL.**
  Measured across 34 boots -- same package, same map, same locked pose,
  window forced to a fixed rect: 0 differing pixels between separate
  processes, and 0 between three shots inside one life. That makes
  "compare what two different engine lives DREW" a legitimate
  instrument, which is what lets a render question be answered one pose
  per boot with no timing coupling at all.
- **THE TRAP, hit twice: the console `wait` counter advances while the
  engine is still LOADING.** A slow boot photographs the STARTUP SPLASH
  (black, logo, progress bar) -- and all its shots agree with each
  other, so an intra-run stability check sails straight past it. At 105
  tics it caught 1 boot in 22; at 175 tics, 1 in 28. Two shots at a
  fixed offset from a fixed wait are NOT a promise that the map is up.
  What fixed it: spread five shots over ~9 s and use only the last
  three, plus a validity check on the pixels themselves (the lit room
  averaged 77 per channel, the splash 5) with a retry. **A frame needs
  its own validity check exactly like a position track does** -- and
  the failure mode is the dangerous direction: two arms that both
  caught the splash would have been reported as "the same picture".
- Second contamination source, caught by HARN-17's own detector: one
  boot logged `GB_VIEWLOCK 8 5.80 4.75` (eight corrected tics, up to
  5.8 deg) and its frame differed from the reference in 97.8% of the
  crop. The lock CORRECTS the pose but the camera is interpolated
  between tics, so a corrected nudge still lands in a frame. Retry any
  boot whose lock reports a non-zero hit count, and add `+set
  use_mouse 0` when the run injects no mouse gestures of its own.

## `SpriteRotation` snaps a VOXEL's drawn facing; `SpriteAngle` does not (GameBuilder VOXROT, measured 2026-08-02, 4.14.3)

Asked because Cheello's Voxel Doom is said to offer "rotate in 45-degree
snaps like the original sprites". **The engine has no such option** --
the whole VOXELDEF vocabulary is spin / placedspin / droppedspin /
angleoffset / zoffset / overridepalette / pitchfrommomentum /
useactorpitch / useactorroll, the only voxel cvar is `r_drawvoxels`
(on/off), and neither local copy of that pack ships a cvar or menu for
it. So it has to be built, and this is the mechanism, measured on 34
engine lives (`F:/GameBuilder/tools/voxel_rot_probe.py`,
`logs/voxrot-20260802-195134.txt`).

- **`Actor.SpriteRotation` (native double, `zscript/actors/actor.zs:104`,
  property :354, `A_SetSpriteRotation` :1029) REACHES THE VOXEL PATH.**
  Held per tic at `round(angle / 45) * 45 - angle`, an asymmetric voxel
  renders in eight discrete facings while `angle` -- what AI, aim and
  movement read -- stays smooth. The engine's own marker on the deciding
  frame reads `angle=40.000000 sprot=-40.000000` while the picture is
  pixel-identical to the angle-0 picture: facing and rendering really do
  part company.
- **The signature, in differing pixels against each mode's own 0-degree
  frame** (one pose per engine life):

  | true angle | snap OFF | snap ON (floor 45) |
  |---|---|---|
  | 10 | 313 | **0** |
  | 20 | 425 | **0** |
  | 30 | 715 | **0** |
  | 40 | 813 | **0** |
  | 50 | 940 | 888 |

- **Nearest-45 is the rule to ship, and its edge is where it should be.**
  With `floor(a/45 + 0.5)*45`, true angles 0/20/22 draw as ONE facing
  (0 differing pixels) and 23/30/44 as the NEXT (888, and 0 between
  themselves) -- the bucket boundary sits at 22.5 deg, which is what the
  original 8-rotation sprites do. `floor` was used only for the headline
  table because it puts the jump at exactly 45.
- **`+SPRITEANGLE` / `Actor.SpriteAngle` DOES NOT reach the voxel path,
  and it is the property a reader reaches for first.** A voxel actor
  declaring `+SPRITEANGLE` with `SpriteAngle` pinned at 0 turned with
  `angle` anyway: 813 differing pixels over a 40-degree turn, the SAME
  813 the ordinary voxel moves. (The arm is not broken -- at true angle
  0 it is pixel-identical to the ordinary voxel.) So: SpriteRotation for
  voxels, and do not spend an hour on SpriteAngle.
- **VOXELDEF `AngleOffset` composes with the snap.** The same KVX
  reached through `{ AngleOffset = 20 }` is drawn exactly as the plain
  one at true angle 20 (425 differing pixels against the plain 0-degree
  frame -- the identical 425 the plain voxel measures at true angle 20),
  and with snapping on, true angles 20 and 40 remain pixel-identical to
  0. A constant offset simply rotates the whole eight-facing set; it
  does not break the snapping. Worth knowing because Cheello's pack puts
  `AngleOffset = 270` on several items.
- **Cost.** The whole recipe is one `floor`, one subtract and one double
  field write per actor per tic -- no allocation, no state change, and
  34 boots logged zero script errors. It was NOT benchmarked at scale
  and should not be claimed to be free; the cheap form is to recompute
  only when the actor's angle has changed since last tic.
- **Blast radius: rendering only, as far as the package can show.**
  Nothing in `uzdoom.pk3`'s ZScript reads `spriteRotation` except the
  declaration, the property, `A_SetSpriteRotation` and a deprecated
  `GetSpriteRotation` in `compatibility.zs`. `angle` is untouched, which
  the measurement confirms from the other side.
- **Not measured, and worth measuring before it is relied on:**
  `+INTERPOLATEANGLES` (the flag exists -- exe string `INTERPOLATEANGLES`
  -- and it is OFF by default; with it ON the drawn facing would slide
  between snaps instead of jumping), and the software renderer
  (`RenderVoxel@swrenderer` is a different code path from the
  `FVoxelModel` one the hardware renderer uses; everything above was
  measured on the default hardware renderer).

**Say what this snapping IS, because it is not quite what "like the old
sprites" implies.** `SpriteRotation` quantizes the actor's WORLD facing.
That reproduces the effect people actually miss -- a monster that TURNS
pops between eight facings instead of sliding round. It does NOT
quantize the VIEWING angle: walking around a stationary snapped voxel
still changes its picture continuously, because it is a 3D model in
perspective. That follows directly from measurements already in hand
(`r_drawvoxels` 1 vs 0 moves 9247 pixels, so the subject really is a
model; and a 10-degree change in the relative orientation moves 313),
so it needs no separate boot -- but it is the difference between this
and a true 8-rotation sprite set, and a claim of "sprite-accurate" would
be wrong. Quantizing the viewing angle instead WOULD need the viewer's
own angle, and `SpriteRotation` is shared play-scope actor state -- the
same trap as `player.camera` in the third-person-camera section, where
a render preference derived from `consoleplayer` differs per node.
Road-mark it; do not reach for it casually.

Two pipeline facts from the same session, both cheap:

- **A voxel probe does not need anyone else's art, and should not use
  it.** `F:/WolfDoom/tools/voxel/kvx.py` writes KVX and was verified
  byte-for-byte against 530 shipped models; a hand-built asymmetric grid
  (a post with one arm) round-trips through that same parser and loads
  in the engine. Asymmetry is the whole requirement -- a symmetric
  subject cannot show rotation at all.
- **Ship a real sprite lump for a voxel actor's frame even though the
  voxel replaces it.** It costs nothing, guarantees the sprite NAME
  registers, and hands the harness its best control: toggling
  `r_drawvoxels` between 1 and 0 swapped 9247 pixels, which is what
  proves the thing being measured is the voxel and not the fallback.

## An exit that WORKS, and the two ways it lies about working (GameBuilder V11, measured 2026-08-02, 4.14.3)

Two sections above measured what a level exit IS (a LINE special) and
what its number is (243 / 244, plus a mandatory activation field). This
one is what a generator learns when it emits one for real and drives a
player into it: `F:/GameBuilder/tools/exit_gate.py`, four engine lives
over a real DOOM II, every number read out of the engine's own map data
and its own `WorldUnloaded` event.

The good news first: **it works exactly as the probe said.** A compiled
UDMF line carrying `special = 243; arg0 = 0; playercross = true;` ends
the level when the player walks over it, in PLAY-TEST mode, over a real
IWAD, with `line.activation` reading back as `1` (`SPAC_Cross`); with
`playeruse = true` it reads back `2` (`SPAC_Use`), the walk-over does
NOTHING, and `Activate(player, 0, SPAC_Use)` ends the level.

**`WorldUnloaded` is the honest signal for "the level ended", and its
`e.NextMap` is the destination actually chosen.** Not `Level.NextMap` --
the secret arm's `e.NextMap` came back as the SECRET destination while
`Level.NextMap` still named the normal one. Two cautions that make it
usable: the event ALSO fires when the engine shuts down, and then names
no next map, so a non-empty destination is what separates a real exit
from a quit; and the next map's own load is a second, independent route
to "it really ended" that is worth waiting a full 8 s for (1.5 s lost it
every time).

**Trap 1: a line is crossed by the actor's BOUNDING BOX, not by its
centre.** The level ended at tic 38 with the player's centre at x=156.0
and the line at x=160.0 -- the player's own `radius` is 16. A crossing
detector written against `pos.x >= lineX` therefore reports "the player
never reached the line" about a run in which the exit demonstrably
fired. Use the actor's own `radius`, read off the actor.

**Trap 2, and it is the quiet one: if the map `secretnext` names DOES
NOT EXIST, `Exit_Secret` silently becomes `Exit_Normal`.** Measured with
everything else correct: the engine printed `Level.NextSecretMap` as
`GBMAP03`, the line carried `special = 244`, the player crossed it, and
`WorldUnloaded` reported `next=GBMAP02` -- the NORMAL destination --
followed by `Unable to open map 'GBMAP02'`. Nothing warned that the
secret exit had been demoted. So a harness that packages only the map
under test cannot tell 243 from 244 at all: BOTH destinations have to be
real maps in the package before the two specials are distinguishable.
(This is also why "the two ids are told apart by DESTINATION" needs the
destinations to exist, not merely to be declared.)

**A pattern worth keeping for any gate over a SHIPPED package: put the
stimulus in a second `-file`.** The engine takes several `-file`
packages, and a later one's MAPINFO overrides an earlier one's `map`
block. So a harness can add its own `StaticEventHandler` -- a scripted
drive, a line census, a use-activation -- WITHOUT putting harness
machinery into the shipped game, and then measure the shipped markers.
The stimulus is instrumented; the signal being judged stays the product's
own.

**And the one that is only a nuisance until it costs you an hour:** the
intermission screen waits for a keypress, and an unattended run has
nobody to press one. `nointermission` on the map (or on `defaultmap`) is
what makes a level transition observable without a human at the desk.

## Making a PLAYER fly, and doing it inside a FROZEN level (GameBuilder FLY-01, measured 2026-08-02, 4.14.3)

A first-person level editor has to let the builder leave the ground -- and
this is a case where reading the engine's own `player.zs` answers the whole
question, while two of the three obvious guesses are simply wrong. Measured
with four engine lives, one probe handler driving all of them identically
(`F:/GameBuilder/tools/fly_probe.py`; `logs/fly01-20260802-222518.txt`).

**`bFly` + `bNoGravity` on the pawn IS the engine's own flight state, and
every movement path already keys off exactly those two.** Read out of
`zscript/actors/player/player.zs`:

  * `ForwardThrust`: `if ((waterlevel || bNoGravity) && Pitch != 0)` pushes
    `Vel.Z` by `-move * sin(pitch)` -- so look up, walk forward, and you
    RISE. That is the Minecraft-creative feel for free, with no new key and
    no new code.
  * `CheckJump`: `else if (bNoGravity) Vel.Z = 3.;` -- jump becomes a steady
    climb while held.
  * `CheckMoveUpDown`: `if (waterlevel >= 2 || bFly || CF_NOCLIP2)` turns
    `cmd.upmove` into `Vel.Z = Speed * upmove / 128.`
  * `HandleMovement` skips the air-control clamp when `bNoGravity`, so a
    hovering player steers at full speed instead of drifting.

**Set BOTH flags or flight silently does not take.** `CheckCheats()` runs at
the top of every `PlayerThink` and contains
`else if (!bFly && !Default.bNoGravity) bNoGravity = false;` -- so
`bNoGravity` alone is wiped one tic later, every tic. `bFly` is what makes
the engine leave it alone. (`bFlyCheat` would additionally protect against
`PowerFlight.EndEffect` clearing `bFly`, but nothing in uzdoom.pk3 ever
WRITES that flag, so whether it is settable at all is unmeasured -- and an
unsettable flag name is a load-time script error that takes the package
down. Re-asserting the two flags per tic covers the same case without
guessing.)

**`player.cheats |= CF_FLY` DOES NOTHING when set from ZScript.** The bit
exists (`constants.zs`, `1 << 4`) and nothing in uzdoom.pk3's ZScript reads
it -- the handling is C++ somewhere the bit alone does not reach. Its arm
was indistinguishable from the do-nothing control: `bFly` 0, `bNoGravity` 0,
`onground` 1, and the player fell 128 -> 0 units exactly like the control.
Worth recording because "just set the fly cheat" is the first thing anyone
reaches for.

**`mo.Gravity = 0` holds an altitude and CANNOT CLIMB.** Measured: 0.0 units
of sag over six seconds, and `128.0 -> 128.0` under a full-speed
`CheckMoveUpDown` drive, because `bFly` stays false and the engine's own
vertical control then takes its no-flight branch. This is the
`player.onground` lesson from section 4 in another costume -- replace a
physics effect and you lose the engine state every other path keys off, and
"does not fall" is not "can go up".

**Flight WORKS UNDER `Level.SetFrozen(true)`, and so does the fall.** All
four arms above ran in a frozen level with the builder's `timefreezer` mask
set (the FREEZE-01 recipe), and every one of them behaved exactly as it does
unfrozen: the control fell, the flight arm climbed and hovered, `frozen=1`
throughout. That follows from what the freeze actually stops -- the level's
thinkers and particle ageing -- and the exempt player's `Tick` still runs, so
gravity still acts on the builder. The practical consequence for an editor:
**an editor freeze does NOT give you a stationary builder, and flight is the
thing that does.**

**Through-walls must ride on the CHEAT BIT, not on `bNoClip`.** `CheckCheats`
derives `bNoClip` from `player.cheats` every tic, so a direct `bNoClip` write
is undone before the next move (the same trap `bNoGravity` has). Set
`player.cheats |= CF_NOCLIP` instead -- unlike `CF_FLY`, this one demonstrably
works, and it needs no `sv_cheats`. And **do not reach for `CF_NOCLIP2`** if
the two are meant to be independent: it forces `bNoGravity` on, i.e. it
bundles no-clip and flight. Measured, four combinations, one engine life
each: the three engine flags follow the two requests exactly, and a drive
into a level's border wall travelled 63.6 units solid against 1447.4 with
no-clip on -- the EFFECT, not only the flag.

**Driving a player UP from a harness: call the engine's own
`CheckMoveUpDown()`.** No channel can press a key in a BACKGROUND engine
window (raw input follows the foreground), so a scripted run has to drive
the pawn -- and the honest way is `players[0].cmd.upmove = N;
players[0].mo.CheckMoveUpDown();` from `WorldTick`, the same virtual
`PlayerThink` calls on the same code path a real `+moveup` takes. The reason
to prefer it over a velocity write is that it is also a CONTROL: with flight
off, the engine's own else-branch looks for an `ArtiFly` in the player's
inventory, finds none, and does nothing at all. The identical stimulus that
lifts a flying player provably moves a walking one zero units.

**And a body with no gravity COASTS.** Stopping such a drive at a target
altitude overshot it by ~67 units, because the pawn keeps whatever `Vel.Z`
it was last given until friction eats it. Enforce a target by taking the
residual velocity away (`if (mo.vel.z > 0) mo.vel.z = 0;`), not by stopping
the push -- an instrument that reports "hover at 96" while sitting at 163 is
measuring something other than its claim.

**Two bind facts, read out of the engine at boot rather than remembered**
(`Bindings.GetBinding(scan)` for a key, `GetKeysForCommand` + `NameKeys` for
a command -- both work from a `play`-scope handler):

  * **F (DIK 0x21) and G (0x22) are UNBOUND** in this build's defbinds, which
    is what made them safe as editor toggles.
  * **`+moveup` is `PgUp` and `+movedown` is `Ins`** by default. So a player
    who is `bNoGravity` already has working fly-up/fly-down keys, and a HUD
    can name them -- provided the session starts from a fresh config, which
    is the only way those defaults are guaranteed to be what the user has.

**`stop` is a ZScript KEYWORD.** `double stop = cvarOr(...)` is a load-time
parse error -- "Unexpected 'stop', expecting identifier" -- and the engine
refuses the whole package with the section-7 signature (log ends at
`LoadActors`, one `Script error` line names the file). It joins
`action` / `auto` / `states` / `out` in the reserved-word list above. Same
family, same cost: cheap to hit, invisible until the engine will not load.

**Harness lesson from the same session, and it is the WIN-00 instrument
family with the camera moved instead of the sampler.** A pixel-counting gate
(HARN-15) was given a FLYING arm, and it passed with a median of **0**
hologram pixels where the walking baseline measures 518: from three courses
up, a level view draws the editor's ghost on distant ground, below the band
that gate deliberately crops. Every assertion fired, and every one fired
against nothing. *A change to the POSE is a change to the instrument's field
of view; an arm that relocates the subject owes a check that the subject is
still in frame.*

## Putting the engine window INSIDE an app: SetParent loses, an OWNED window wins (GameBuilder WIN-04, measured 2026-08-02/03, 4.14.3)

The obvious way to dock a game window into a host application is
`SetParent` + `WS_CHILD`. On this engine it WORKS for everything except the
one thing that matters, and the failure is total and unrecoverable. Eleven
engine lives over a bare Win32 host window
(`GameBuilder/tools/dock_probe.py`; `logs/win04-dock-probe-*.txt`), every
number read out of the engine's own log or off the screen.

**`SetParent` + `WS_CHILD`: everything but input.**

- The reparent TAKES and HOLDS. Style bits stripped, `SetParent` to the
  host, one `SetWindowPos` with `SWP_FRAMECHANGED`: the child sits exactly
  in its pane, and over three seconds of sampling it reports **one distinct
  rect** -- the engine does not fight it and does not resize itself back
  out. Reparent AFTER the settle (the 640x480 creation stub, WIN-00) and
  pre-size with `win_w`/`win_h` so the reparent is not also a resize.
- It RENDERS. 826 252 painted pixels across the pane, **zero** pixels of
  the host's background showing through, and 1 696 300 pixels changing
  between two frames 0.45 s apart -- a live picture, not a frozen one.
- The SIM stays alive (`GB_POS` keeps flowing), `SetWindowPos` refits it to
  a new pane rect, and `SetParent(NULL)` + the saved styles put it back to
  an ordinary top-level window at its old rect with input working.
- **AND THEN: a `WS_CHILD` window can never be the foreground window, and
  this engine reads RAW INPUT, which follows the foreground window.**
  Immediately after the reparent the child is STILL the foreground window
  (it inherited that state, so keyboard and wheel keep arriving, and it
  even survives a blink that way). The first time the host is fronted --
  i.e. the first time the user clicks any panel in the app -- the docked
  engine goes deaf, and **nothing gets it back**:
  `SetForegroundWindow(child)` leaves the host in front;
  `AttachThreadInput` + `SetFocus` demonstrably DOES give the child
  keyboard focus (`GetGUIThreadInfo` confirms it) and it still hears
  nothing; and **a real physical left-click inside the child's own client
  area does not even produce a scancode** -- the engine's log shows exactly
  two events for the whole arm, the ones sent while it still had the
  foreground. CONN-07's `push()` refuses honestly with `reason: "focus"`.
  Focus is not the currency here; FOREGROUND is.
- Corollary worth keeping: `front_and_focus()`-style helpers make it
  WORSE. Handing the foreground to the child's own parent is what breaks
  it. The measured recipe for a reparented window is *do not touch focus
  at all* -- which is also the standing no-focus-fights rule, arriving at
  the same answer from the other direction.

**An OWNED top-level window wins, and is what shipped.**
`SetWindowLongPtr(GWLP_HWNDPARENT, app_hwnd)` + stripped frame +
`SetWindowPos` over the pane, with `SWP_NOACTIVATE`:

- still TOP-LEVEL, so it can be the foreground window and raw input
  reaches it exactly as before -- input, wheel and CONN-07's `push()` all
  behave identically to the undocked case (`push()` measured ok, gesture
  arrived, foreground returned to the app);
- **clicking it fronts it**, which is the recovery WS_CHILD cannot do;
- Windows keeps it permanently above its owner with **no z-order fight**:
  with the owner fronted, the census still read 826 252 of the engine's own
  pixels and **0** of the owner's showing through;
- it hides with the owner when the owner is minimized and comes back on
  restore, and it gets no taskbar button or alt-tab entry of its own;
- across a blink the new window is re-attached and input arrives **with no
  click of any kind**;
- `SetWindowLongPtr(GWLP_HWNDPARENT, 0)` + the saved styles detaches it
  cleanly, so the undocked fallback is a real path.
- Trap for any code that FINDS the window: an owned window has an owner, so
  the usual `EnumWindows` filter `not GetWindow(hwnd, GW_OWNER)` stops
  finding it. Prefer unowned, then accept owned.
- Trap for any code that ASKS whether it is a child: `GetParent` returns
  the OWNER for a top-level owned window, so it reports "has a parent" for
  exactly these windows. Only the `WS_CHILD` style bit distinguishes them.

**THE ENGINE STOPS REDRAWING WHEN IT IS NOT THE FOREGROUND WINDOW, AND
THAT MAKES EVERY PIXEL CENSUS A TIMING PROBLEM.** This is not new
behaviour and it is not caused by docking -- `i_pauseinbackground 0` keeps
the SIM running, not the renderer -- but docking is where it bites, because
a docked window spends its life next to an app the user is clicking.
Measured while adding a docked mode to the ghost census: the docked run
reported **min == median == max == 936 lit pixels over 30 samples** where
the undocked baseline the same night reported **80 / 652 / 1873** on the
identical arm. The window was there, the crop was verifiably its own
pixels, and every frame was the same held image.

Two consequences for harness design, and the second one is the one that
would have shipped:

- *Ask whose pixels these are DIRECTLY.* `WindowFromPoint` at all four
  corners and the centre of the crop, resolved to the window (or a child of
  it), beats "is the right process in the foreground" -- it catches partial
  occlusion the foreground test cannot see, and it keeps working for a
  window that is not the foreground.
- *That is necessary and NOT sufficient.* Region ownership answers WHERE;
  it says nothing about WHEN. A census needs `owns_rect(...) AND the engine
  is the foreground window`, and a run that cannot establish the second is
  UNMEASURED, never a pass. Docked or not, front the engine and verify it
  took before reading pixels.

**One more measured oddity, worth knowing before it looks like a defect:**
the first synthetic keystroke sent to a *freshly relaunched* engine is
sometimes swallowed even though the engine already holds the foreground
(arrived on attempt 2 of 4, repeatedly; the undocked arm in the same run
arrived on attempt 1). Latch-poll the gesture and report the attempt count
rather than asserting on one shot -- the playbook's own "never assert at a
fixed tic" rule, applied to input delivery. A one-shot assertion here
convicts docking of something the separate window does too.

## ZScript trig is DEGREES and Python's is radians, and at the cardinals
## they disagree in the last bits (GameBuilder FMT-07, measured 2026-08-03, 4.14.3)

A rule that exists twice -- once in ZScript for the live ghost, once in
Python for the pipeline -- can agree about a POINT and disagree about
what that point ROUNDS TO. Measured by HARN-08 on the first run of a new
aim payload (`logs/harn08-20260803-021928.txt`):

- **`cos(270)` in ZScript is exactly 0. `math.cos(math.radians(270))` in
  Python is -1.8e-16.** ZScript's trig takes and returns DEGREES and
  special-cases the cardinals; Python converts to radians first and pi/2
  is not representable. So a ray marched due south from x=112 stayed at
  x=112.0 engine-side and drifted to 111.99999999999999 in Python.
- **That is harmless until something SNAPS.** 112 is a cell centre, which
  is exactly halfway between two 32-unit grid corners -- a tie -- so the
  two sides snapped to corners a whole cell apart and the parity harness
  (correctly) failed. The fix is to quantize the sample to a coarse step
  (1/16 of a map unit) BEFORE snapping, with the same tie rule on both
  sides: `floor(v * 16 + 0.5) / 16`. The tie the quantization introduces
  of its own sits at 1/32-unit offsets, which no exact-arithmetic sample
  lands on.
- **And never `round()` in Python for a rule ZScript mirrors:** Python
  breaks ties to EVEN (`round(3.5) == 4`, `round(4.5) == 4`), which no
  other language here does. Write `floor(v/q + 0.5)` on both sides.

The general lesson, worth more than the arithmetic: **a duplicated rule
has to be tested at the values where the two implementations are most
likely to differ, and for geometry those are the cardinals, the cell
centres and the boundaries** -- not the "typical" cases. A parity harness
whose poses are all off-axis will pass forever over this.

## Driving a MULTI-CLICK editor gesture headlessly (GameBuilder FMT-07, measured 2026-08-03, 4.14.3)

The interesting state of a two-click tool is the one BETWEEN the clicks,
and nothing outside the engine can press a mouse button in its window
(this playbook, CONN-07: no posted message reaches a background engine,
and raw input follows the foreground). Three facts that made that state
testable:

- **Let the handler drive its own gates.** A harness-only cvar that makes
  the StaticEventHandler call its OWN click entry points at scripted tics
  exercises the real state machine -- the swallow window, the busy latch,
  the aim validity, the click branches -- rather than a copy of it. The
  probe should print only WHICH PHASE it is in; what happened must be
  read back from the shipped markers, or the probe is grading itself.
- **Two clicks need a MOVED AIM between them, and turning the pawn's
  own `angle` from WorldTick does it** (then re-run the aim derivation
  before the second click). Two clicks at one aim land on the same target
  and a correct tool refuses the second -- so a drive that does not move
  proves only that the refusal works.
- **Give the second click RETRIES.** The corner a turn lands on may
  legitimately be unbuildable, and a gate that failed on that would be
  measuring the room's shape rather than the gesture. Three attempts,
  spaced, and report which one took.
- **Let the run LIVE long enough.** The first version of this gate asked
  the smoke harness for 8 position markers and the engine was killed
  after the second phase, which read as "the drive never reached the undo
  phase". A run cut short is not a measurement -- size the wait from the
  drive's last tic, not from habit.

