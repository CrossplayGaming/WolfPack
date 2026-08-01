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
