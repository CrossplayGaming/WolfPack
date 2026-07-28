# WolfPack

**Wolfenstein 3D, together.** A faithful one-for-one remake of
Wolfenstein 3D on the UZDoom engine, with multiplayer as the headline:
co-op through the original campaigns and head-to-head deathmatch, plus
optional modern controls — all behind the original's menus, fonts, and
feel.

**This repository contains no game assets.** It is a *compiler*: it
builds the game from your own legally-owned Wolfenstein 3D data at
setup time. Nothing copyrighted is committed or distributed, and no
build of it may be sold or paywalled.

## Features

- One-for-one fidelity: movement, enemy behavior, damage math, secrets,
  bosses, episode endings — verified against id's GPL source release,
  with the receipts in [docs/FIDELITY_CHARTER.md](docs/FIDELITY_CHARTER.md)
- **Co-op** (2-4 players): pick episode and skill together in a lobby
  built from Hans's boss level, then play the campaign
- **Deathmatch**: curated 1v1 arena with frag/time limits, respawn
  cooldowns, and away-from-killer spawns
- Friend-friendly hosting: invite codes on the clipboard, automatic
  router setup where possible, no terminals, no server rental
- Player Setup: four uniform colors so you can tell each other apart
- Modernization menu (all off by default): mouse vertical aim, jumping,
  crouching
- Cheat menu faithful to the classics

## Building your copy

1. **Engine**: place a UZDoom build in `engine/` (so that
   `engine/uzdoom.exe` exists).
2. **Game data**: put your Wolfenstein 3D files (`*.WL6`) in
   `gamedata/`, or let the build find your Steam install automatically.
3. **Requirements**: Python 3 with `pip install pillow pefile`.
4. Run `play.bat` once — the first run extracts and converts
   everything, then launches the game. After that, double-click
   `WolfPack.vbs` for a console-free launch.

## Multiplayer quickstart

Host: in-game menu → **Multiplayer** → pick co-op or deathmatch → the
game restarts and shows your invite code (already on the clipboard) —
send it to your friends, click **Start Hosting**.

Join: copy the host's invite code, then Multiplayer → **Join a Game**.

Everyone needs their own built copy (same version). `multiplayer.bat`
option 3 runs a two-window test on one PC.

## Development

- Conversion contract: [docs/FIDELITY_CHARTER.md](docs/FIDELITY_CHARTER.md)
- Engine lessons learned: [docs/UZDOOM_PLAYBOOK.md](docs/UZDOOM_PLAYBOOK.md)
- Netgame architecture: [docs/MP_AUDIT.md](docs/MP_AUDIT.md)
- Behavior spec: id Software's GPL Wolfenstein 3D source
  (github.com/id-Software/wolf3d), cloned locally under `reference/`
  (not committed)

## Credits & legal

- id Software — Wolfenstein 3D and its GPL source release, the
  behavior specification for everything here
- The UZDoom / GZDoom / ZDoom lineage — the engine this runs on
- Wolfenstein is a trademark of ZeniMax Media Inc. This is an
  unaffiliated, non-commercial fan project; the name is used only to
  describe compatibility, and your own copy of the game is required.
- Project code is GPL, matching its ancestors.
