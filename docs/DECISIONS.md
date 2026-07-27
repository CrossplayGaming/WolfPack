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

## D-004 - Mouse defaults: horizontal turn only (2026-07-26, user)

Default mouse behaviour is **horizontal turn only**: `freelook 0` (no
vertical aim, as the original) *and* `m_forward 0` (mouse Y does nothing).

Note this is a deliberate deviation from the handoff's "everything OFF
except strafing" rule: the original's mouse Y moved the player
forward/back, so strict 1992 behaviour would leave `m_forward` at its
default. The user prefers the modern feel here.

The classic Y-axis-moves-you behaviour becomes a **Modernization menu
toggle** ("Classic mouse") when that menu is built - it restores
`m_forward`. Revisit whether the shipping fidelity-first default should
flip back at that point.

## D-005 - Intermission BJ breathing: second frame sourced from Spear

BJ_Breathe (WL_INTER.C) alternates L_GUYPIC and L_GUY2PIC. Measured in
the user's data:

- WL6 chunk 43 and chunk 84 are BYTE-IDENTICAL (hash ce8d15f5af, 9152
  bytes each). Verified across three separate WL6 copies (Steam, and two
  other local installs) - it is the release, not the extractor. Only two
  104x88 pictures exist in the whole WL6 VGAGRAPH.
- Spear's pair DOES differ, and its SECOND frame hashes to exactly the
  WL6 picture (ce8d15f5af). So Spear's FIRST frame (fdcdc8aa16) is the
  pose the WL6 release lost - the same BJ with the chest and arm shifted
  (2140 of 9152 pixels differ).

Decision: when the WL6 frames are identical AND the user's own Spear
data is present, make_assets uses the Spear frame as the second
intermission frame so BJ breathes. With WL6 data alone the animation
runs but shows no change, which is faithful to that release.

No assets ship either way - both come from the user's own files.

## D-006: Menu structure — ECWolf-style (2026-07-27)
User decision: the menu tree follows ECWolf (New Game / Options / Load /
Save / Read This! / End Game / Back to / Quit; Options gathers Control,
Sound, Display, Automap), not the original's flat list. Geometry,
colours, fonts, window/outline styling and the gun cursor stay
one-for-one with WL_MENU.C. Unlike Doom, entering the menu REPLACES the
attract screens entirely and switches to MENUSONG (WONDERIN); backing
out returns to the attract loop's title page — the original's
US_ControlPanel semantics, which our menu-based attract makes free.
