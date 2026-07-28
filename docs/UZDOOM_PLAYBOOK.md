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
