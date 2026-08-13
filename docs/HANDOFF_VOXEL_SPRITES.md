# Handoff: automated Cheello-class voxelization of the Wolf3D sprite set

> **2026-08-13: partially superseded.** The production pipeline this
> document speculated about now EXISTS and is proven end to end — see
> `HANDOFF_VOXEL_PIPELINE.md` (tools, modes, engine wiring, a complete
> six-state character shipped in CCFPS). Read that first; this document
> remains valuable for its Wolf-specific fidelity ideas (space carving
> from the 8 rotation sprites, the pixel-diff harness, the lathe for
> symmetric props) which the new pipeline does not cover.

Written 2026-08-02 in the Crystal Caves FPS conversation, for the WolfDoom
conversation to pick up. Eric asked whether Cheello's Voxel Doom result --
pixel-faithful voxel models replacing sprites -- can be approached in an
AUTOMATED way for all of Wolf3D's sprites and objects. Earlier chat
skepticism predated tooling that now exists and is proven. Answer: yes,
with a three-archetype pipeline and a fidelity harness. Reasoning and
design follow; no code written yet.

## Why Wolf3D is tractable where Doom needed an artist

1. **Enemies carry 8 rotation sprites** (stand/walk) at 45 degrees --
   enough views for SPACE CARVING (visual hull): solid 64^3 block, carve
   outside each view's silhouette, surviving shape matches every
   canonical silhouette BY CONSTRUCTION. Colour each surface voxel from
   the view it faces most squarely (front view wins ties) -> from every
   canonical angle the model shows ~the original sprite. A guard's 8x4
   walk sprites collapse into 4 voxel models the engine rotates freely.
2. **Most props are rotationally symmetric** (lamps, columns, barrels,
   well, plants, chalice, food): LATHE archetype -- revolve each sprite
   row's colour profile around the vertical axis. Front pixel-identical,
   all other angles physically round. Likely the strongest tier.
3. **Fixed small palette + KVX carries a native 256 palette** -> voxel
   colours are the sprites' exact palette indices, zero quantisation.
4. Engine path shared with CCFPS: UZDoom, KVX + VOXELDEF.

## The three archetypes

| Archetype | Input | For | Quality expectation |
|---|---|---|---|
| HULL | 8 rotation views | enemy stand/walk frames | silhouette-exact at 8 angles; smooth interpolation between |
| LATHE | 1 view + symmetry | round props | near-perfect front, correct roundness |
| INFLATE | 1 view | attack/pain/death frames, bosses, asymmetric props | front exact, depth ballooned (distance transform); back mirrored. For enemy death frames use the same actor's stance HULL as a depth prior |

Per-sprite override file (JSON, Eric-authority like CCFPS's
material_verdicts.json): archetype switch, depth scale, axis, seam fixes.

## The fidelity harness (the honesty mechanism)

Render every produced voxel model orthographically at the 8 canonical
angles; pixel-diff against the original sprites; per-frame match
percentage in a scored report. Eric reviews the worst offenders;
overrides fix them as data. "Close to Cheello" becomes a measured claim.
Known honest gap: Cheello ADDED unseen-side detail (sculpted ears, boot
treads); the hull interpolates smoothly instead. Selective hand-passes in
MagicaVoxel on top of generated models are the optional last mile.

## Tooling that already exists (in F:\CrystalCavesFPS, reuse directly)

- `tools/voxel/voxelize.py` -- own mesh voxelizer + .vox writer +
  slice/three-view preview PNGs (proven on the Meshy dinosaur, colours
  intact). The .vox writer and preview code transfer as-is.
- `tools/voxel/glb_to_obj.py` -- headless Blender bridge (not needed for
  sprite-derived voxels but part of the shared voxel stack).
- EGA/palette tooling patterns; for Wolf use the VSWAP palette instead.
- CCFPS playbook lessons: KVX is the engine-reliable format; VOXELDEF
  for scale/offsets; engine-side proof FIRST (generate a trivial KVX,
  see it standing in-game) before mass production.

## Build order proposed for the WolfDoom session

1. KVX writer (documented format; CCFPS also needs it -- write once,
   share). Engine proof: any voxel standing in a WolfDoom map.
2. Sprite extraction interface: WolfDoom already parses VSWAP; expose
   sprites as (frame, angle) -> 64x64 indexed bitmaps + the
   classification table (which indices are 8-rotation sets, which are
   props) from WOLFSRC's sprite enum.
3. LATHE archetype first (props are the easy win and prove the KVX+
   palette path end to end).
4. HULL archetype + colouring + interior fill.
5. INFLATE + stance-hull depth prior.
6. Fidelity harness + scored report; Eric's override pass.
7. VOXELDEF wiring + in-game A/B (sprites vs voxels toggle).

## Open questions for Eric in the WolfDoom conversation

- Scope: enemies + props both? Weapons/HUD stay 2D (recommended).
- SoD assets too, or Wolf3D first?
- Per-frame model count budget on Android (TURBOSTEIN lineage) -- the
  perf check from CCFPS's asset strategy applies here doubly.

## Addendum: Eric''s reconstruction pipeline + the synthesis (2026-08-02)

Eric''s path for single-view cases (proven in spirit by the CC dinosaur):
sprite -> ChatGPT generates a PRISTINE high-res multi-angle turnaround
sheet (clean render style, no pixel art, no outlines -- Meshy handles
this far better than raw 64x64 sprites) -> Meshy multi-image to 3D ->
AI texture from the original colours -> voxelize through the proven
chain -> derive ALL remaining frames from the one reconstructed actor
(posing / preset sampling / archetype animator) rather than per-frame
reconstruction.

THE SYNTHESIS -- "AI proposes the flesh, the sprites impose the skeleton
and the skin":
1. SILHOUETTE CARVE (hard constraint): the voxelized AI model is carved
   against the original sprite silhouette at the canonical angle -- for
   8-view actors, against all eight (the model must live inside the
   sprites'' visual hull). AI excess is deleted mechanically; deficits
   are flagged by the fidelity harness, never auto-filled.
2. COLOUR STAMP: canonical-angle surfaces take the sprite''s exact
   palette pixels; AI texture survives only on never-seen surfaces.
3. Fidelity harness scores the result like everything else.

Default route per class (verdict table, Eric-ruled):
- Wolf 8-view enemies, symmetric props: SPRITE-DERIVED (hull/lathe/slab,
  no AI, deterministic).
- Floor-flat items: SLAB (they are floor drawings; 1-2 voxels thick).
- Asymmetric single-view props, bosses, CC creatures (no rotations
  exist): ERIC''S AI-RECONSTRUCTION route + carve/stamp enforcement.
- Attack/pain: per-actor model posed (Eric''s architecture) where the
  actor has one; stance-hull warp as the no-model fallback.
- Deaths: posed model per frame or progressive flattening toward the
  corpse SLAB; final corpses are always slabs.
