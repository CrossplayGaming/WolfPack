# Netgame Audit Ledger

Phase 1 (DONE, this commit): per-player score/lives/nextExtra/oldScore in
WolfGameState; kill points attributed through the DamageMobj source;
pickups/1-ups award the toucher; floor-exit bonus to every in-game
player; death consumes the dying player's life and rolls back their
score; net events (cheats, MLI, newgame) act on e.Player; HUD draws
CPlayer's numbers; victory-freeze clearing loops all players.

Phase 2 (co-op minimum - each site needs a DESIGN decision, not a tag):

- enemies.zs (~14 sites) + enemies_more.zs + bosses.zs: the sim targets
  "the player" (players[0]) for sight, chase, dodge, and shooting - the
  original has exactly one. Needs nearest-visible-player selection with
  the original's rules applied per candidate (SIGHT-001 facing test,
  area connectivity per player: areabyplayer is ALREADY plural in the
  original's data model, which helps).
- deathcam.zs: camera staging assumes player 0 is the watcher; killPos
  now tracks the true killer. Policy: all players watch (freeze all,
  reposition all? or killer-only camera, spectators frozen in place).
- player.zs victory staging: any player can trigger; policy: freeze and
  spin ALL players; BJ runs at the trigger player.
- level.zs playerPos/tracking helpers: verify which player they mean
  under co-op (noise origin, area tracking).
- intermission.zs: per-player tally columns (original has one player's
  numbers; co-op needs a decision: show own stats vs everyone's).
- Death policy (user decision pending): respawn at floor start
  original-style vs spectate to floor end; what happens to the shared
  floor state on a solo death in co-op (currently: full floor restart -
  wrong for co-op).

Maps: player 2-8 starts + deathmatch starts still absent from
convert_udmf output - required before any 2-player test.

Player identity (2026-07-27): wolf_skin userinfo cvar (0-3 =
grey/blue/red/tan) drives a Tick-time sprite remap in WolfPlayer from
the BJ1 set to the BJ2-4 ramp recolors. Userinfo replicates per player
and archives locally, so every node computes the same remap in
lockstep and the choice survives restarts - including the quit-and-
relaunch hop into a netgame session. Picker: Multiplayer > Player
Setup, with a live stand-sprite preview.

Lobby + 1v1 arena (2026-07-27): LOBBY map generated from Hans's level
(convert_udmf make_lobby): boss/victory tiles stripped, all 8 co-op
starts clustered in the big pillared hall (user spec), no exit yet -
episode doors and skill switches come with the lobby flow. Campaign
MAP09 untouched except deathmatch: curated 1v1 starts replace the
max-spread eight - one in the starting room (34,58 N), one in Hans's
chamber (34,11 S), per user spec. DM_OVERRIDES in convert_udmf.py is
the place for more curated arenas.

Lobby flow (2026-07-27): WolfLobby handler drives the LOBBY map. West
aisle bands (6, between the pillar-stub rows) select episode, east
aisle top 4 bands select skill, walking into Hans's chamber commits:
ChangeLevel(episode start, NOINTERMISSION|RESETINVENTORY, skill) in
lockstep on all nodes. Host-only (player 0); joiners get a message and
a persistent overlay showing the pending choice. Selection is walk-
over and re-triggerable; only the commit needs deliberate travel.
mp_launch.ps1: co-op hosts now start in LOBBY; deathmatch hosts start
straight in the MAP09 arena with -nomonsters (Hans doesn't referee).
Verified headless (wolf_dbg_lobby): warped through west band 2 + east
band 0 + chamber, landed on MAP21 at skill 0.

DM spawn telefrag (2026-07-28, user repro + headless confirm): with
only the two curated 1v1 starts, the engine's random initial spawn put
both players on the SAME spot - at first spawn no body exists yet to
block the second pick - and the mutual telefrag left both dead on a
red screen at 0%. Fix: sv_spawnfarthest 1 on every deathmatch launch
(each spawn picks the spot farthest from living opponents - also the
right 1v1 respawn behavior: you respawn in the room away from your
killer). Headless 2-node repro went from 2 telefrag obituaries to 0.

Arena sanitize (2026-07-28, user repro: Hans present + gold door
locked): deathmatch pass in WolfLobby.WorldLoaded destroys all
WolfEnemySim (the custom sim never carried the engine monster flag, so
-nomonsters missed it) and all victory triggers (walking the corridor
would end the match). Door unlock lives in WolfDoor.PostBeginPlay
(if deathmatch, lock 0) NOT the sweep - map-spawned actors run
PostBeginPlay on the first TICK, after WorldLoaded, and the args copy
overwrote an unlock attempted there. Probes: enemies=1 victory=3
cleared, 0 doors locked at t=30, 0 telefrags.

DM QoL round (2026-07-28, user test feedback):
- Respawn + death animation: the netgame Die path left deathPhase 0,
  so the overridden DeathThink did NOTHING - the engine's native death
  handling (view lowering to the floor + press-fire respawn) never
  ran. Netgame DeathThink now hands off to Super. One fix, both
  reports (dead forever + no death animation).
- Rulesets: DM hosting (real + local test) prompts for frag limit
  (default 10) and time limit (default none) - engine-native
  fraglimit/timelimit, serverinfo so the host's values replicate.
  sv_samelevel keeps the arena on MAP09 after a limit ends the match.
  UNTESTED: what our custom intermission shows when fraglimit trips.
- Sync audit: all consoleplayer uses confirmed ui/render scope; sim is
  clean. User-visible "out of sync" pending diagnosis: permanent
  divergence (true desync, engine prints consistency failures) vs the
  ~2-tic lockstep view lag amplified by the dual-window rig.

DESYNC ROOT CAUSE (2026-07-28, user screenshot "Out of sync with:
Player (2)"; kills computed on one node only): netgame client
prediction re-runs the local player's Tick per frame and restores the
pawn but NOT global state - so UpdateFace's US_RndT consumption
advanced each node's RNG stream unevenly. Beacon-proven: rng index
diverged at the first 30-tic sample with both players motionless;
after the CF_PREDICTING guard in WolfPlayer.Tick, 19/19 beacons
identical and zero out-of-sync messages. All damage rolls ride that
stream, hence the one-sided deaths.
