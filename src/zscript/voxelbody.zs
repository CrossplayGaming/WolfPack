// Voxel player body: the longer animation cycles the KVX sets carry.
//
// The models come from the owner's own animated GLBs through
// tools/voxel, and they are richer than the sprite states they replace:
//
//   state    sprite frames   voxel poses
//   Spawn    BJ?S A               7
//   See      BJ?W ABCD            6
//   Missile  BJ?F A               3   (as BJ?A, the shoot set)
//   Pain     BJ?P AB              2   (already matches)
//   Death    BJ?D ABCD            7
//
// Those extra frames CANNOT go in the States block. The voxel pack is an
// optional separate download, so its sprite frames are not there in a
// plain build - and a state that names a missing frame is a load error,
// which would break the game for everyone who never downloads it.
//
// So the states stay exactly as they are and this drives `sprite` and
// `frame` directly each tic instead, which the renderer is perfectly
// happy with: VOXELDEF binds a voxel to a sprite+frame token, and the
// lookup happens at draw time, not at state-compile time.
//
// Everything here is off unless the pack is loaded (the WOLFVOX marker
// lump), and it runs inside WolfPlayer.Tick after ApplySkin, so the
// uniform recolor has already chosen BJ1/BJ2/BJ3/BJ4 and this only picks
// the frame within it. Lockstep-safe: derived from replicated state
// (the actor's own state and tic counter), identically on every node.
class WolfVoxBody
{
    // poses per kind, in the order vox_to_kvx named them (A, B, C...)
    const IDLE_POSES  = 7;
    const RUN_POSES   = 6;
    const SHOOT_POSES = 3;
    const DEATH_POSES = 7;

    // tics per pose. Idle breathes slowly; the run matches the sprite
    // cycle's 4 tics so firing mid-stride keeps the stride; the shoot
    // set has to fit inside Missile's 10 tics.
    const IDLE_TICS  = 9;
    const RUN_TICS   = 4;
    const SHOOT_TICS = 3;
    const DEATH_TICS = 5;

    // the pistol walk-fire cycles (BJ?G forward / BJ?K backward): a full
    // stride, paced like the run so movement speed matches the feet
    const PFIRE_POSES = 7;
    const PFIRE_TICS  = 4;

    // the long-gun pair (BJ?L / BJ?M), the plain backward walk (BJ?B),
    // and the knife stab (BJ?T, played once per attack)
    const LFIRE_POSES = 6;
    const LFIRE_TICS  = 4;
    const BWALK_POSES = 7;
    const BWALK_TICS  = 4;
    const STAB_POSES  = 5;
    const STAB_TICS   = 2;

    static bool Present()
    {
        return Wads.CheckNumForFullName("WOLFVOX") >= 0;
    }
}
