# Wolf3D Fidelity Checklist — Easily-Overlooked Mechanics

Companion to the Wolf3D → UZDoom project. Every item below is a behavior the recreation must
reproduce (or consciously toggle) that is easy to miss because Doom's engine does it differently
or not at all. Ground truth: the GPL Wolf3D source (WOLFSRC — esp. WL_ACT1/WL_ACT2, WL_AGENT,
WL_STATE, WL_PLAY) cross-checked against ECWolf behavior and DOSBox observation. Items marked
[VERIFY] have details that must be read from source, not trusted from this doc or anyone's memory.

## 1. Map-data systems (converter must translate these or levels are silently wrong)

- **Area/room codes + sound propagation.** Floor tiles carry area numbers; firing a weapon alerts
  all enemies in the connected area. Opening a door JOINS its two areas until it closes. Closed
  doors block sound; open ones pass it. Do NOT inherit Doom sector sound flooding — reimplement
  area-based alerting from tile data. This governs the entire stealth/alert feel.
- **Patrol turn-tiles.** Invisible directional markers (object plane) redirect patrolling enemies.
  Converter must emit them; patrolling guards consult them per source movement code.
- **Difficulty-gated spawns.** Thing codes encode skill tiers (easy/medium/hard variants of the
  same enemy/item placements). Map skill filtering must match original tier boundaries. [VERIFY
  exact code ranges]
- **Decoration blocking table.** Solid vs walk-through per object type is a source table, not
  intuition (columns/barrels block; many props don't). Port the table verbatim.
- **Secret elevator routing.** Standard vs secret exit per floor; secret floors return to the
  correct next floor. Elevator switch flips visually when used.
- **Pushwall data + travel distance.** Fixed tile travel per the source (stop early when blocked).
  [VERIFY distance + blocked-by-actor semantics] Pushwalls block sight/sound while intact
  (polyobject lines, not models — see doors research).
- **Ambush ("deaf") tile markers.** A specific tile code marks enemies that ignore sound and
  activate on sight only. [VERIFY code + interaction with area alerting]

## 2. Enemy AI subtleties (actor code)

- **Enemies open doors** (already flagged): chase code triggers door use; dogs CANNOT open doors
  and wait at them.
- **Alert rules:** instant reaction through open doors; no alerting through closed doors; reaction
  delay varies by enemy type and difficulty [VERIFY tables].
- **Hit chance vs player:** function of distance, player movement (moving reduces enemy accuracy),
  and enemy type. Port the roll tables exactly.
- **Bosses:** deaf until seen (sight-activated regardless of sound), NO pain states (never flinch),
  drop key items on death where applicable, trigger DeathCam.
- **DeathCam:** one-time replay of boss death from a second camera angle. Iconic, near-universally
  forgotten in remakes.
- **Ammo drops:** humanoid enemies drop a used clip on death; amounts per type per source [VERIFY
  amounts; note dropped-clip value differs from placed clips].
- **Fake Hitler / projectile enemies:** fireball behaviors, syringes (Schabbs), rockets (bosses)
  each have distinct speeds/damage [VERIFY]. Hitler is a two-phase fight (mech suit, then Hitler).
- **Pac-Man ghosts (E3 secret floor):** move through walls, damage on contact, invulnerable.
  Requires a noclip enemy class.
- **Chase pathing:** tile-based movement with the original's direction-selection logic — not
  Doom's A_Chase. Dogs must be adjacent to bite.

## 3. Player / combat feel

- **No weapon bob. No head bob.** Weapon sprite is fixed; camera height constant. Disable all Doom
  bobbing explicitly.
- **Single shared ammo pool** (bullets) across pistol/machine gun/chaingun; auto-switch to knife at
  zero; knife melee range/rate per source.
- **Trigger semantics:** knife and pistol are semi-automatic (one attack per press); machine gun
  and chaingun are held-fire with distinct cadences [VERIFY tic counts per state].
- **Hitscan model:** 2D distance-based damage rolls (different dice for point-blank vs far) —
  port the exact roll code, including the player's version vs the enemy's version.
- **Movement:** keyboard turn acceleration ramp; run modifier speeds; collision is tile-based with
  corner slide — verify feel against DOSBox side-by-side. No jump/crouch/freelook verbs (disable).
- **Classic mouse mode:** original mouse Y moves the player forward/back. Ship as "classic mouse"
  toggle (off by default for modern hands, present for purists).
- **Screen flashes:** damage red and pickup yellow/white flash intensities + durations per source.
- **Fizzle-fade:** the pseudorandom pixel dissolve (LFSR sequence in source) on player death and
  certain transitions. Recreate the actual algorithm, not a crossfade.
- **Status bar face:** idle look-around, escalating blood states, and the gatling grin when picking
  up the chaingun. God-mode face variant if cheats included.

## 4. Rules / progression

- **Keys reset every floor; weapons/ammo carry.** Health/ammo caps 100/99.
- **Death:** restart current floor with pistol loadout; lives decrement; score handling on death
  per source [VERIFY exact reset semantics]. Extra life at 40,000 points; 1-Up item gives full
  health + ammo bonus.
- **Pickup denial:** health items refused at full health (item remains); same-weapon pickups grant
  ammo [VERIFY amounts].
- **End-of-floor tally:** kill/secret/treasure percentages, floor time vs par, par-time bonus
  points, perfect-ratio bonuses [VERIFY bonus values].
- **Episode end sequences:** victory text/picture screens per episode; E1 BJ run-and-jump yell
  sequence. These are content, not skippable ceremony.
- **Difficulty modifiers:** damage scaling on easiest skill [VERIFY], enemy counts via spawn
  gating, reaction/fire-rate differences.
- **Save anywhere** (original had 8 slots) — quicksave/quickload extends this; must serialize full
  actor + door + pushwall + area-alert state.

## 5. Presentation constants

- Solid-color floor/ceiling per map (no textures) as shipped default; per-level color table from
  source.
- VGA palette fidelity; 320x200-on-4:3 pixel aspect option per launcher convention.
- Adlib/IMF music and digitized speech from user VSWAP/AUDIO files; per-enemy alert/death voice
  lines are data, not new assets.
- No automap in original. Ship automap as clearly-labeled QoL toggle, off by default.
- Menu structure/skill screen (difficulty faces) recreated in original style per launcher
  philosophy; classic cheat codes (MLI etc.) = fan-service inclusion decision.

## 6. Spear of the Destiny deltas (if included at launch)

- Continuous 21-floor structure (no episodes), different bosses (Trans, Barnacle, UberMutant,
  Death Knight, Angel of Death), demon-dimension finale sequence, different key/boss-drop flow,
  its own par times and ceiling colors. Treat as a profile of the same engine, config-driven like
  the Keen launcher's per-episode handling.

## Verification protocol reminder

Every [VERIFY] resolves by reading WOLFSRC and confirming in DOSBox — never by community wiki
alone. Add each resolved constant to the charter with a source-file reference so the harness can
assert it. Feel items (door timing, turn accel, fizzle rate) get side-by-side capture comparison,
same discipline as Keen.
