# WolfPack — "Making Of" companion document

A structured starting point for a video. **Not a script.** Every section
is talking points, facts you can check, and suggested visuals — the
words stay yours.

Facts in here are pulled from the actual project record (git history,
the design docs, the shipped builds). Where a number appears, it is
real.

---

## 0. The disclaimer, up front and short

Say it once, plainly, then never circle back to it.

Suggested substance (your words):

- You are not a programmer. You are a designer, a player, and someone
  who knows exactly what Wolfenstein 3D is supposed to feel like.
- This project was built with an AI coding assistant doing the
  implementation, with you directing, testing, judging, and making
  every creative call.
- Why that is a sensible fit here rather than a shortcut:
  - **The spec already exists.** id Software released Wolfenstein 3D's
    source code under the GPL. This is not invention; it is
    *translation* — moving known, documented behavior onto a modern
    engine. That is exactly the kind of work automation is good at.
  - **The volume is inhuman.** 81 levels, 861 sprites, 51 music tracks
    across two games, hundreds of exact constants — all of which must
    be extracted, converted, and cross-checked. Doing it by hand is
    thousands of hours of transcription with a mistake in every
    hundredth line.
  - **Nothing is stolen.** The project ships zero copyrighted assets.
    It is a *compiler*: it builds the game out of the copy of
    Wolfenstein you already own.
- Then drop it. The rest of the video treats the AI as what it was: a
  fast, tireless, occasionally overconfident collaborator.

**Tone note:** the strongest version of this section is confident and
brief. No defensiveness. The work speaks.

---

## 1. What WolfPack actually is (30–60 seconds)

- A one-for-one recreation of **Wolfenstein 3D** *and* **Spear of
  Destiny**, running on UZDoom (a modern descendant of the Doom engine).
- "One-for-one" means the real thing: movement speeds, enemy reaction
  times, damage rolls, door timings, the fizzle-fade death effect — all
  matched to the original source code, not to memory or feel.
- The headline addition: **multiplayer.** Co-op through the original
  campaigns and deathmatch. Wolfenstein 3D never had either.
- Optional modern comforts, all off by default: mouselook, jumping,
  crouching.
- It ships as a **compiler**, not a game. You point it at your own
  Wolfenstein data and it builds you a playable copy.

**Visual:** side-by-side of original Wolf3D and WolfPack running the
same room. Then the multiplayer lobby with two players in it — the shot
that instantly says "this is not the 1992 game."

---

## 2. The spine of the story

If the video needs one sentence to hang on, it is this:

> **The whole project is really about one question: how do you know it's
> right?**

That thread is genuinely present from the first commit to the last, and
it escalates:

1. **Write down what "right" means** before writing any game code (the
   fidelity charter).
2. **Build machines that check it** (self-tests, probes, sync beacons).
3. **Discover the machines share your blind spots** (the audits that
   passed while the game was visibly wrong).
4. **Rebuild the checks to be independent of your own assumptions** (the
   final structural build gates).

And underneath it, the honest counterpoint: **every single one of the
deepest bugs was found by a human playing the game**, not by any check.
That tension is the most interesting thing in the project, and it is
true.

---

## 3. Timeline — four acts

Total span: **four calendar days**, 26–29 July. **152 commits.** Roughly
11,400 lines of game code and 4,500 lines of build tooling.

Don't present this as "look how fast." Present it as "look what the
shape of the work actually was" — because the shape is the interesting
part, and roughly half the commits are *fixes to the other half*.

### ACT I — "Write the spec first" (Day 1, morning)

The first **six** commits contain **no game code at all.** They are
documents — and tools whose only job is to produce more documents.

- A **fidelity charter**: 275 entries, each one a constant or rule
  extracted from id's source with a file-and-line citation. Walk speed.
  Enemy hit chance by distance. Door open time. The exact 17-bit
  pseudo-random sequence behind the death-screen dissolve.
- A **coverage ledger** that inventories every file in id's source and
  marks what has been accounted for — so nothing gets silently skipped.
- **Rule adopted on day one:** fidelity claims must cite the source. Not
  "this feels right," not "I remember this." A line number.

Then the extractors: tools that crack open the original game's data
files and pull out levels, textures, sprites, sound, and music.

**1 hour and 19 minutes after the first commit, the first level loads in
the new engine.** (12:18 → 13:37, if you want the timestamps on screen.)

**Visual:** the charter document scrolling — it looks like a legal
brief. Then that first ugly, texture-less E1M1 load.

**Talking point:** the temptation is to start with the fun part. Writing
the spec first is what made the rest checkable — you cannot verify
against a feeling.

### ACT II — "Build the whole game" (Day 1, rest of it)

In a single day, in order: doors → pushwalls → decorations → the guard
enemy → weapons → HUD → items and keys → sound and music → four more
enemy types → level progression → the death sequence → all eight bosses
→ the boss-death camera → the victory screen → the ending text screens.

**Worth being honest about:** this is where the AI's speed is genuinely
the story. It is also where the errors start, and they are *invisible*
ones — an enemy facing the wrong way, a sound that never plays, a sprite
that silently doesn't register.

Good specific beats:

- **The invisible enemies.** Guards spawned, moved, shot at you — and
  rendered as nothing. The engine needs sprite names *declared* in a
  particular place, and a missing declaration doesn't error; it just
  makes the thing invisible.
- **Enemies facing the wrong way.** Wolfenstein encodes spawn directions
  East/North/West/South. The player uses North/East/South/West. Same
  four numbers, different meaning — so every enemy stood at 90° off.

**Visual:** a montage of the game filling in — grey boxes to textures to
enemies to HUD.

### ACT III — "Erase the host engine" (Day 2)

An entire day spent on presentation, with a strict goal: **no visible
trace of the engine it runs on.** Anyone who has played a Doom mod knows
the tell — the menus give it away instantly.

What that took: a custom menu stack rebuilt in Wolfenstein's layout, the
original's fonts, its mouse cursor, its sounds on every keypress, its
red-and-grey color scheme, its exact 13-pixel menu spacing, the attract
loop, the high-score table.

And where the engine's own screens couldn't be replaced, they were
*recolored* into the Wolfenstein palette so they at least belong.

- **A nice small detail:** the pre-game art was rendering square instead
  of widescreen-correct. Fixing it properly meant measuring, in one
  frame, how the engine actually transforms images — rather than
  guessing. That measurement became a permanent note in the project's
  engine playbook.
- **The letterbox treatment:** static art gets a tiled stone background
  and a beveled frame, borrowed in spirit from Commander Keen. It's the
  one place the project deliberately adds something the original didn't
  have — and it exists because 4:3 art on a 16:9 screen needs *somewhere*
  to live.

**Visual:** the menu evolution. Doom's menu → the Wolfenstein rebuild.
Then the framed title art.

### ACT IV — "Multiplayer, and the education" (Day 2 evening → Day 4)

This is the heart of the video, because this is where the project stops
being transcription and starts being **design**.

Wolfenstein 3D is single-player to its bones. Its code says "the
player," singular, everywhere. Making it multiplayer means finding every
one of those assumptions.

The work, in order:
1. An audit of everything that assumed one player (score, lives, enemy
   targeting, the areas the game thinks are "awake").
2. Spawn points for players 2–8 in all 81 maps — generated, since the
   original maps only have one.
3. **The first two-player game connects.**
4. A friend-friendly hosting layer: invite codes on the clipboard,
   automatic router setup, no terminals, no server to rent.
5. A **lobby** built out of Hans Grösse's boss level — walk into an
   alcove to pick your episode, walk into another for difficulty, walk
   into Hans's chamber to start.
6. Deathmatch: a curated 1v1 arena, weapon drops, respawn rules.

**The best story in the project lives here — see §5.**

Then, in the last stretch: **Spear of Destiny**, the standalone sequel.
Its own 21 floors, five new bosses, its own ending. And adding it turned
into an unplanned stress test of everything built so far — because a
pipeline that serves *two* datasets exposes every assumption that only
ever served one.

---

## 4. How the collaboration actually worked

Be concrete here. This is the part people haven't seen before.

**The loop, honestly:**

1. You describe what you want, usually in plain language and often as a
   feeling ("the door frame should look like the original," "it needs to
   be clear which direction the player is shooting").
2. The AI reads the original source code, implements it, and — crucially
   — writes an automated check where one is possible.
3. **You play it.**
4. You report what's wrong, usually with a photo of your TV.
5. The AI diagnoses, fixes, and adds a check so that class of bug can't
   come back silently.

**What you brought that the AI could not:**

- **Judgment about feel.** "The frame greys are too bright." "The moss
  stone clashes with this section." "That cursor should look like it's
  pointing."
- **The actual testing.** Every deep bug in this project was found by
  you playing, not by any automated check. That is not a small point.
- **Art.** You painted the multiplayer player sprites yourself — and
  made a design call the original never did: eight *rotated firing
  frames*, so other players can tell which direction you're shooting.
  Wolfenstein never needed those, because its enemies always face you.
- **Scope and taste.** What ships, what waits, what the thing is called.

**What the AI brought:**

- Reading 30-year-old C and translating it exactly.
- Volume without fatigue — 81 maps, 861 sprites, 51 soundtracks.
- Building test harnesses nobody would build by hand: a two-machine
  network simulator, a probe that fires a weapon 300 times and counts
  the shots, a "sync beacon" that logs both players' game state and
  diffs them.
- Documentation as it went: the charter, an engine playbook of hard-won
  gotchas, a multiplayer audit ledger.

**What the AI got wrong — say this plainly, it's the honest part:**

- Fixed the same bug incorrectly more than once.
- Built an audit that passed while the game was visibly broken.
- Broke a working feature while "fixing" it (twice — see §5).
- Repeatedly claimed something was verified when the verification had a
  hole in it.

The pattern that matters: **the AI was reliable at doing and unreliable
at knowing when it was done.** The human was the opposite. That's the
partnership, and it's worth saying out loud.

---

## 5. The five best stories (pick two or three)

These are the moments with real narrative shape. Each has a symptom, a
wrong turn, and a satisfying cause.

### A. The gun that barked
**Symptom:** In Spear of Destiny, enemy soldiers' rifles made a dog
bark.
**Cause:** Both games store sounds by number. Wolfenstein's sound #21 is
a rifle. Spear's #21 is a dog attack. The code used Wolfenstein's
numbering for both games.
**Why it's good:** it's instantly funny, instantly understandable, and
it's the perfect entry point to the project's central problem — an
index that's *valid* in both games but *means* something different in
each.

### B. The desync detective story
**Symptom:** In co-op over the internet, the two players' games slowly
drifted apart. Shots were visible, but a kill would register on one
screen and not the other.
**Investigation:** A "beacon" was added — both machines log their exact
game state every second, and the logs get compared. With both players
standing perfectly still, the shared random-number stream had *already*
diverged.
**Cause:** The status bar's BJ portrait — the one that glances
left and right — draws a random number every tick to decide when to
glance. The engine's lag-hiding system re-runs your own player several
times per frame, and each re-run pulled extra numbers. Since all weapon
damage comes from that same stream, the two machines were rolling
different damage. **The face on the HUD was desyncing the game.**
**Why it's good:** the cause is absurd, the diagnosis is rigorous, and
the fix is one line.

### C. The jump that wouldn't
**Symptom:** The "enable jumping" toggle did nothing.
**Two wrong fixes:** first blamed the setting's on/off values; then
blamed how the setting was saved. Both plausible. Both wrong.
**Real cause:** Wolfenstein has no momentum — you move at full speed or
not at all — so the movement code was replaced wholesale. The original
movement code also quietly computed *"is the player standing on the
ground?"* Without it, the engine believed the player was permanently
airborne, and you cannot jump while already in the air. It refused
silently, at every setting.
**Why it's good:** it's the clearest example of a whole class of bug —
replacing something and losing a side effect you didn't know it had.

### D. The typo from 1992
**Symptom (the one you actually saw):** in Spear, the machine gun and
the chaingun looked like the same weapon.
**Backstory:** this was the *fifth* fix in a row for the same area, and
you asked the pointed question — *why do these fixes keep being
partial?*
**Real cause:** id Software's own source header contains a typo. In a
long list of sprite names, one entry — `MACHINEGUNATK3` — is missing
the `SPR_` prefix every other entry has. The tool reading that list
matched only properly-prefixed names, so it **silently skipped that
slot and shifted every following number by one.** Every weapon fix had
been built on a shifted table, so each one moved the error instead of
removing it. It had also quietly broken the *Wolfenstein* chaingun.
**The lesson:** the audit couldn't catch it because the audit used the
same reader. It was self-consistent and self-consistently wrong.
**The fix that mattered:** a check that compares the *number of names
read* against the *number of sprites actually in the game data*. Both
games were short by exactly one. That check takes a second and would
have caught it immediately.
**Why it's good:** a 33-year-old typo, an AI confidently building on
top of it, and a human asking the right question to break the loop.

### E. The negative title screen
**Symptom:** Spear's title art looked like a photo negative.
**Cause:** most of the game's art shares one color palette — but Spear's
title screen and its nine ending screens each carry *their own*. Decode
them with the wrong palette and the colors invert.
**The embarrassing part:** the ending screens had already been fixed
earlier that same day. The title was missed because the fix was a
hand-written list, and hand-written lists go stale.
**The response:** stop maintaining a list. Add a rule — *every custom
palette in the game data must be either used or explicitly declared
unused.*
**Why it's good:** it's the cleanest illustration of the project's final
lesson, and it's self-deprecating in a way that lands.

---

## 6. Explaining the tech without losing anyone

Short, reusable analogies. Pull as needed.

- **What a source port is.** The original game is a car built for 1992
  roads. A source port rebuilds the same car so it drives on modern
  roads — same handling, new tires, still legal to drive.
- **Why "one-for-one" is hard.** It's not "make it feel like
  Wolfenstein." It's "the guard must take exactly this long to notice
  you, and his shot must have exactly this chance to hit at this
  distance." Feel is an opinion. These are numbers, and they're
  checkable.
- **What the compiler thing means.** WolfPack isn't the game. It's a
  machine that *builds* the game out of the copy you already own.
  Nothing copyrighted ever changes hands. (Also the honest reason it can
  be public at all.)
- **What "indexed by number" means** (needed for the best stories):
  the original games store everything in big numbered lists — sound #21,
  wall #98. Two different games have *different* lists. If you use one
  game's numbering to read the other's data, you get something real and
  completely wrong. Every hard bug in the Spear phase was this.
- **What lockstep multiplayer is.** Nobody sends "the enemy is here."
  Both machines run the identical simulation and only send button
  presses. It's efficient and exact — and it means that if the two
  simulations *ever* disagree by one number, they drift apart forever.
  Hence the paranoia about shared randomness.

---

## 7. Numbers worth putting on screen

- **4 days**, 26–29 July · **152 commits**
- **~11,400 lines** of game code · **~4,500 lines** of build tooling
- **275** cited fidelity entries in the charter
- **2 complete games** — 60 Wolfenstein floors + 21 Spear floors
- **861 sprites** and **27 / 24 music tracks** per game, all generated
  from the user's own data at build time
- **0 copyrighted assets** in the repository
- **5 automated build gates** that must pass before a build is accepted
- Multiplayer for **2–4 players**, co-op and deathmatch

---

## 8. The ending — what this actually demonstrates

Resist the urge to make this either an AI advert or an AI cautionary
tale. The truthful version is more interesting than both:

- The AI wrote essentially all of the code, and it worked — a faithful
  two-game recreation with functioning internet multiplayer, in four
  days, by someone who doesn't program.
- The AI also could not tell when it was wrong. It repeatedly reported
  success on things that were visibly broken on a television ten feet
  away.
- What closed that gap was not a better AI. It was **a human who kept
  playing the game and asking pointed questions**, and a discipline of
  turning every answer into an automated check that doesn't depend on
  anyone's confidence.
- The final five build gates are the artifact of that. Each one exists
  because a bug got past everything else and reached a real player.
  That's not a failure of the process — that *is* the process.

A good closing beat, if you want one: the project's own engineering
notes now contain a line that reads roughly *"existence checks cannot
catch a wrong-content index."* It's written to a future version of the
same AI, by the same AI, after being wrong about it three times. Make of
that what you will.

---

## 9. Suggested visual beats (for the edit)

| Moment | Shot |
|---|---|
| Cold open | Two players in the same Wolfenstein corridor, shooting each other |
| The spec | The fidelity charter scrolling — dense, cited, unglamorous |
| First load | The bare, texture-less E1M1 |
| Day-one montage | The game assembling itself in fast cuts |
| The menu | Doom's menu, then the Wolfenstein rebuild, hard cut |
| Multiplayer lobby | Walking the aisle, signs changing gold as they're selected |
| The bug wall | Your actual TV photos — the brown-rock door, the negative title, the bazooka-pistol |
| The barking gun | Just play the audio. No explanation needed for the laugh |
| The typo | The line from id's 1992 header, highlighted |
| Close | The Spear title screen, correct at last, with its music |

---

## 10. Things to fact-check before you publish

- Whether you want to name the AI assistant and model, and how.
- The trademark line: Wolfenstein is ZeniMax's; the project is
  unaffiliated and non-commercial and requires your own copy. It's worth
  stating once, clearly, in the video or the description.
- Credit id Software for releasing the source under the GPL — none of
  this exists without that decision.
- Credit the UZDoom/GZDoom/ZDoom lineage for the engine.
- If you show the multiplayer working, it's worth noting your brother
  was in another state — the internet test is more impressive than a
  LAN test and people will assume LAN.
