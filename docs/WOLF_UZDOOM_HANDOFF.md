# Wolf3D → UZDoom Faithful Recreation + Co-op — Project Handoff

Companion docs: `WOLF_FIDELITY_CHECKLIST.md` (the curated catalog of easily-overlooked mechanics —
treat as highlights, not ground truth; the Coverage Ledger in Phase 0.5 below is ground truth).
This project follows the conventions proven in the user's completed work: Hovertank 3D port, two
Catacomb 3-D recreations, and the seven-game Commander Keen launcher, all UZDoom/SDL projects
built AI-assisted with mathematical fidelity verification. Read those handoffs' philosophy if
context is missing; this doc is self-contained on specifics.

## Project summary

Recreate Wolfenstein 3D (and Spear of the Destiny) in UZDoom as **one-for-one faithful by
default** — ECWolf-grade accuracy as the shipping configuration, not an option buried in menus —
with **intuitive multiplayer co-op** layered on top, and PvP as a labeled experiment. User-supplied
game data (WL6/SOD files); nothing copyrighted ships.

Positioning against the field, verified current:
- **ECWolf**: the fidelity standard, but no multiplayer, not UZDoom, no modern launcher UX.
- **AFADoomer's Wolf3D TC**: UZDoom-family, but enhanced-by-default (textured floors/ceilings,
  added features) — the user checked personally and confirmed the fidelity-first gap remains.
- **Zandronum Wolf mods**: MP exists but on old tech without fidelity discipline, and Zandronum
  cannot run ZScript, which rules it out entirely for this project (see Netcode below).

The unclaimed spot: *accurate by default, modern presentation, and the first genuinely good
Wolf3D co-op experience.* Co-op is the headline — Wolf3D never had it — with the fidelity work as
the trust foundation, same as the Keen launcher.

## Distribution model (settled)

Compiled PK3 + launcher; user drops their WL6 (and optionally SOD) data in. Launcher detects
versions (1.1/1.2/1.4 registered, shareware, Spear) and reports what's present/missing. Steam/GOG
sell the data, so setup docs have a clean "buy it here" path. Ship no original assets anywhere,
including test fixtures — the harness uses checksums and trace files, never game data.

## Source material and oracles

- **Spec:** the GPL Wolf3D source release (WOLFSRC). This is the complete behavior of the game;
  treat it the way the Keen project treats the reconstructions.
- **Behavioral oracles (dual):** ECWolf (the accuracy reference implementation) and the original
  in DOSBox. Where they disagree, DOSBox wins and the discrepancy gets documented.
- **Reference prior art (read, don't copy):** ECWolf source for behavior interpretation questions;
  AFADoomer's TC threads for the documented polyobject pitfalls (see Doors section). Do not port
  code from either — the sim is reimplemented from WOLFSRC for provenance cleanliness and GPL
  simplicity (the whole project is GPL regardless; cleanliness here is about fidelity claims, not
  license conflict).

## Licensing and naming (settled)

- Project is GPL (inherits from engine lineage and Wolf source posture). Source published from
  first release.
- **Do not use "Wolfenstein" in the product name.** ZeniMax/Microsoft actively defends the
  trademark. Follow the user's established naming convention (TURBOSTEIN precedent) — evocative,
  legally distinct. Name is the user's call (open question below).
- Free release, user-supplied data, no monetization attached to this IP. Same posture as all
  prior projects; the site/community philosophy doc governs presentation.

## Architecture decisions (settled)

1. **UZDoom, native multiplayer.** The old netcode fork is resolved: the GZDoom 5.0-line shipped
   its year-long network overhaul (packet-server mode default for internet games — host has no
   delay, per-client delay matches own latency, desyncing clients no longer halt everyone, 64
   player cap, overhauled lobby), and UZDoom carries this forward as a named roadmap priority.
   Zandronum is off the table permanently: its netcode fundamentally cannot run ZScript per its
   own developers. Build on current UZDoom stable; track their netcode releases.
2. **Simulation/presentation split**, as in every prior project. The sim is Wolf's logic at its
   original tic basis with an explicit, documented conversion table to Doom's 35Hz — every
   constant (speeds, reaction delays, door timing, fire cadences) converted on paper first, not
   ad hoc in code. Presentation (resolution, refresh, interpolation, input mapping, menus) is
   modernized freely. No floats in game state.
3. **ZScript for all actor/sim logic.** This is Claude Code's demonstrated strength and the
   verification loop (build PK3 → launch +quit → parse log) is already proven tooling from the
   Catacomb work. Reuse that bootstrap.
4. **Doors and pushwalls are polyobjects, ZScript-driven.** Research settled this: polyobjects
   are the engine-native horizontal slide mechanism (Hexen lineage). The documented AFADoomer-era
   pitfalls and their resolutions:
   - *Renderer bleed*: caused by hand-authored maps lacking void pockets for doors to retract
     into. Our maps are converter-generated — emit door pockets, anchors, unique polyobj IDs, and
     adjacent-door spacing mechanically. The failure mode was human inconsistency; we have none.
   - *Pushwall stop distance*: 2010-era ACS couldn't stop a polyobject after its fixed travel;
     ZScript drives it per-tic with tile-boundary checks and the source's blocked-by-actor
     semantics. Polyobject pushwalls (not models) so sight/sound blocking works — the model
     workaround's known flaw was enemies seeing/hearing through secret walls.
   - *Enemies opening doors*: our guard AI is written from WOLFSRC anyway; its chase code
     includes the door-use check that triggers the polyobject action. Dogs wait at doors.
   - Fallback if UZDoom shows polyobject renderer edge cases: actor/model doors + toggled
     blocking lines. Plan B only; do not start there.
5. **Launcher shell**: same ImGui/SDL architecture as the Keen launcher — data detection,
   zero-touch first run, settings with live apply, controller-first, per-game (Wolf/Spear)
   handling as profiles. New for this project: the multiplayer lobby (Phase 4).
6. **In-game menus are a fidelity target, not launcher chrome.** Recreate Wolf3D's original menu
   system one-for-one — layout, fonts, colors, cursor, sounds, Read This! and all — exactly as the
   Keen launcher integrated settings into each game's original menus so they look like id shipped
   them (the user calls this out as the prior project's best-realized feature; match or beat it).
   New functionality (the Modernization toggles below, co-op entries, launcher-level settings that
   must be reachable in-game) appears as **expansions inside that same visual language**: same
   fonts, same highlight behavior, same sounds, new entries indistinguishable in style from
   original ones. The launcher shell handles out-of-game concerns (setup, lobby); everything
   in-game lives in the recreated menu. Menu appearance/behavior is verified against DOSBox
   side-by-side like any other fidelity item.

## The Modernization toggle list ("Doomify" menu — settled principle, contents to iterate)

A sizable, discoverable list of gameplay-modernization toggles living inside the recreated
original-style menu (per Architecture #6). **Default state: everything OFF except strafing.**
The shipping default is the 1992 experience; each toggle moves one aspect toward Doom-style
modern play. Toggles are individually labeled and individually verified to touch presentation or
input only — any toggle that would alter sim math (movement inertia, jump) is implemented as a
clearly-separated sim variant and excluded from MP unless all players match (lobby enforces).

Initial list (Claude Code proposes additions during Phase 2; user curates):
- **Strafing** (ON by default — the one concession)
- Always run
- Modern mouse (horizontal turn only; disables classic Y-axis move) / mouse sensitivity split
- Freelook + vertical view shear (renderer supports it; sim hitscan stays 2D regardless)
- Doom-style movement inertia (sim-variant class; MP-gated)
- Jump/crouch (sim-variant; MP-gated; expect this to stay a novelty)
- Weapon bob / view bob (visual only)
- Crosshair
- Automap (ECWolf-style capabilities/style per D-003; original had none)
- Depth shading / distance darkening (Wolf renders unshaded; this is the single biggest "looks
  like Doom now" switch)
- Textured floors/ceilings (the AFADoomer feature — present here as an OFF-default toggle rather
  than a default; uses flat colors from the source table when off)
- Positional/stereo sound panning (original playback model when off)
- HUD variants: original status bar (default) / compact / fullscreen with Doom-style readouts
- Par timer + speedrun stats display
- Quicksave/quickload (house feature; arguably QoL not modernization — lives in this menu anyway
  for discoverability)

Each toggle's tooltip states what it changes and that OFF = original behavior. The menu screen
itself is the marketing: one screenshot of this list communicates the entire product philosophy
("it's all here, and it's all off").

## Phase 0 — Fidelity charter

Write the conversion contract before any code:
- Tic-rate mapping table: Wolf's timing basis → Doom's 35Hz, with the rounding policy stated.
- The constants inventory format: every gameplay number gets (value, source file/line, converted
  value, harness assertion ID).
- Difficulty semantics: spawn gating tiers, damage scaling, reaction/fire-rate differences.
- The [VERIFY] items from the fidelity checklist resolved by reading WOLFSRC — never wiki-sourced.
- Decision log format for any place Doom's architecture forces an approximation (target: zero
  gameplay-visible approximations; log proves it).

## Phase 0.5 — Coverage Ledger (the exhaustiveness machine)

The fidelity checklist is curated highlights; this phase makes completeness a bookkeeping fact
rather than a judgment call. WOLFSRC is finite and fully possessed, so "exhaustive" is achievable:

1. **Inventory**: mechanically enumerate every function, state-table entry, #define/constant, and
   global across the source, file by file (behavior concentrates in the actor files, agent/player
   file, state framework, play loop, intermission, and progression code).
2. **Classify** every item into exactly one bucket:
   - `game-behavior` → must be ported; becomes an implementation + harness item
   - `platform` → replaced by UZDoom (VGA, keyboard interrupts, memory manager); listed as
     consciously replaced
   - `data-pipeline` → replaced by extractor/converter (format loaders)
   - `presentation` → recreated per launcher philosophy (menus, text screens, signon)
   - `dead/debug` → deliberately omitted, documented
3. **Completeness check is mechanical**: unclassified count must reach zero. Anything
   unclassified is a gap by definition.
4. **State-table diffing**: the enemy state tables (every state's tics + action function per
   enemy) diff directly against ZScript actor definitions as they're written — the strongest
   per-enemy completeness proof. Build this diff as a repeatable tool, not a one-time check.
5. **Constants flow**: every numeric literal in `game-behavior` code lands in the charter's
   constants table with a harness assertion.

Ledger caveat (documented honestly in-repo): it proves exhaustiveness of *intent* — every source
element consciously handled. Misclassification (e.g., "platform" code with gameplay-visible timing
side effects) is caught by the replay-differential harness, not the ledger. Ledger = coverage;
harness = verification. Both or neither.

## Phase 1 — Pipeline (mostly reused) + vertical slice

- Extractor: MAPHEAD/GAMEMAPS (Carmack + RLEW — same compression lineage as the Catacomb
  extractor; reuse code), VSWAP (walls/sprites/digitized sounds), AUDIO (Adlib/IMF music). Output
  the JSON intermediate per house convention.
- Converter: tile grid → UDMF. Solid-color floor/ceiling per level from the source's color table.
  Doors/pushwalls emitted as polyobjects per the settled architecture (pockets, anchors, IDs).
  Area codes, patrol turn-tiles, difficulty-gated things, ambush markers, and the decoration
  blocking table all translate here — these are the silent-failure items; the converter asserts
  it consumed every tile/object code or fails loudly on unknowns (no silent drops).
- **Vertical slice exit criterion: E1M1 with a correct first door.** Door open speed, auto-close
  delay, blocked-reopen behavior, and sounds measured against DOSBox capture. The first door is
  the fan shibboleth; it gates everything.

## Phase 2 — Single-player sim to ECWolf parity

- Actors from WOLFSRC state tables via the ledger's diff tool; combat math (distance-based rolls,
  both directions), area-based sound alerting, patrol/chase/door AI, bosses (no pain states,
  deaf-until-seen, key drops, DeathCam), Pac-Man ghosts (noclip class), pickups/scoring/lives,
  floor tally with par bonuses, episode end sequences, fizzle-fade (port the LFSR algorithm),
  status face incl. gatling grin.
- Controls: original scheme default (incl. turn-acceleration ramp); everything else per the
  Modernization toggle list (strafe ON, rest OFF). Recreated original menu system built this
  phase, with toggle entries in original visual language (Architecture #6).
- Input-replay regression harness with per-tic state hashes (house standard), plus the
  constants-assertion suite from the charter.
- Save system serializes complete sim state: door timers, pushwall mid-slide positions,
  area-alert state, patrol state. A save that silently resets alert state is a shipped bug.
- SP is independently releasable at this phase's end if the user wants a milestone release.

## Phase 3 — Co-op as designed content

Design decisions (propose defaults, user decides with playtests — these need real humans):
- Spawns: Wolf maps have one start; generate P2-P4 spawns adjacent to P1, with map-specific
  overrides where geometry demands.
- Respawn: arcade-style — dead player respawns at floor entry with pistol loadout, lives shared
  or individual (lobby option), game-over/continue rules defined per lobby.
- Enemy scaling: off by default (fidelity), optional HP/count scaling as labeled lobby options.
- Friendly fire: off by default.
- **The co-op identity feature: per-player arcade scoring.** Individual treasure/kills/secrets
  with a competitive end-of-floor tally screen. Uses entirely original mechanics; turns every
  floor into a friendly rivalry. Build this early — it's the hook.
- Sim determinism in MP: same fixed-tic sim, packet-server mode; desync soak tests automated
  (scripted-input MP sessions with state-hash comparison across clients).

## Phase 4 — The lobby (the actual novel contribution)

UZDoom MP setup today is command-line-and-IP hostile. The launcher makes it humane:
- Host game → shareable code/invite → friend joins from launcher. Automatic version match and
  data-hash verification with clear, human failure messages ("your Spear files differ from the
  host's — here's what to check").
- Port forwarding guidance/UPnP attempt; saved friends list; rejoin-in-progress per packet-server
  capabilities.
- Lobby options surface the Phase 3 toggles (lives, scaling, friendly fire, difficulty).
- Quality bar: "my brother and I played Wolfenstein together in ten seconds." This is the demo
  moment for the reveal video.

## Phase 5 — PvP experiment (labeled, non-blocking)

Hitscan-only mazes = odd PvP space. Last-man-standing with pickups as a bonus mode, expectations
set in-product ("experimental"). Spawn sets generated per map. Do not let this delay co-op; cut
from launch freely.

## Phase 6 — Verification + rollout

- Full DOSBox side-by-sides per episode; speedrun-community-grade checks (par behaviors, secret
  routes, boss patterns); MP soak tests.
- Rollout per the established playbook: community forums first with methodology + receipts
  (side-by-side video), then broad; credits to id's source release and ECWolf as behavior
  reference; AI-assistance disclosed per the site philosophy doc. Reveal video leads with the
  lobby demo — two players in a floor in seconds — then the fidelity receipts.

## Open questions for the user (do not decide unilaterally)

- Product name (TURBOSTEIN-convention; must avoid the trademark).
- Shareware-episode support posture (shareware data is freely distributable — bundle-adjacent
  convenience vs. keep uniform bring-your-own-data posture).
- ~~Automap toggle default~~ RESOLVED (D-003, docs/DECISIONS.md): ECWolf-style, off by
  default, menu toggle.
- ~~Classic cheat codes~~ RESOLVED (D-001): dedicated cheat menu page (Doom-style set, all
  off by default) + authentic MLI always present one-for-one (charter CHEAT-001); text
  overlays/intermission/episode-end screens one-for-one incl. 16:9 posture per D-002.
- Co-op lobby defaults (lives model, scaling) — decide via playtest, not speculation.
- Milestone release of SP-only before co-op lands?

## Pacing model (calibrated to this user — read before scoping)

Do not scope on human-developer time. The user completed Hovertank + two Catacomb recreations in
under a week and the seven-game Keen launcher shortly after, working with Claude Code. Calendar
time = (1) oracle-checked work, which runs autonomously and fast — the extractor, converter,
actor translation, harness assertions, ledger tooling are all this kind; (2) the user's judgment
loop — feel verdicts, co-op design calls, lobby UX — batch these into meaningful playable builds;
(3) **new bottleneck for this project: multiplayer playtests need other humans on schedules.**
Flag MP-dependent decisions early so the user can line up 2-3 playtest partners; automate
everything automatable (desync soaks) so human sessions spend on feel and fun only. The genuine
unknowns are concentrated in polyobject behavior under current UZDoom (Phase 1 slice) and co-op
feel (Phase 3); everything else is Catacomb-shaped.

## Working style (house standard)

- Drive autonomously; pause at the open questions above, phase exits, and anything irreversible.
- Every stage re-runnable end to end; never hand-patch generated artifacts — fix the stage.
- Ambiguities in original behavior: state the ambiguity and its resolution (WOLFSRC reading vs
  ECWolf vs DOSBox observation) explicitly; never guess silently. Where oracles disagree, DOSBox
  wins and the disagreement is documented.
- Self-bootstrapped dev loop per house convention (build, launch +quit, parse logs); the user
  never touches tooling.
