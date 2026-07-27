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
