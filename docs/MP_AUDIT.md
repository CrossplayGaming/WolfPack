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
