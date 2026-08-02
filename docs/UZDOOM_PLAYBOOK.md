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
