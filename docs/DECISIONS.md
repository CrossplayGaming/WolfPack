# Design Decisions Log

User-settled decisions. Each entry: what was decided, what remains proposal-status inside it.

## D-001 — Cheats (2026-07-26, user)

- **Dedicated cheat menu page** inside the recreated original-style menu system (same visual
  language per Architecture #6). Contents: as extensive as UZDoom allows, covering the cheats
  people know — god mode, all weapons, all keys, full ammo, noclip, level warp, resurrect,
  etc. **All off by default.**
- **The authentic MLI cheat ships always**, as sim behavior, one-for-one (effects, overlay
  message, score zeroing — see charter CHEAT-001). It is not a menu item; it's the original
  M+L+I keypress in-game.
- Proposal (user to curate): also keep the original debug-keys path authentic — the
  LShift+Alt+Backspace unlock (WL6 gate: `goobers` command-line param; Spear: `debugmode`)
  opening the Tab-key debug set (Tab-G god, Tab-W warp, etc.), plus optionally surfacing the
  same unlock as a cheat-page entry for discoverability.
- Proposal: in multiplayer, cheats disabled unless host enables in lobby (decide at Phase 3/4).

## D-002 — Text overlays, intermissions, episode ends: one-for-one (2026-07-26, user)

Reiterated fidelity target, now explicit scope:
- **All in-game text overlays** (Message() boxes: MLI response, debug messages, "get psyched",
  pause, quit prompts) — same text, same look, same function.
- **Level-complete scorecard** — counts, count-up animations, sounds, par display, BJ
  breathing/thumbs-up, 100% bonus beeps: identical.
- **Between-level / episode-end text pages** ("artwalls" — the Read This!-style art-framed
  text screens, victory text, episode endings incl. E1 BJ run-and-jump yell sequence) —
  identical.
- **16:9 posture:** extend these screens elegantly to 16:9 to match the in-game look where it
  can be done cleanly; where it can't, use the same solution as the Keen launcher (check
  F:\KeenLauncher for the established approach before implementing).

## D-003 — Automap (2026-07-26, user)

- **ECWolf-style automap capabilities and style** (overlay + full-page modes per ECWolf's
  feature set), **off by default**, enabled via menu toggle. Supersedes the "Doom-style
  overlay" wording in the handoff's Doomify list.
