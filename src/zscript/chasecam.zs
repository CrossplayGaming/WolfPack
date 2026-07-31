// Optional third-person view ("wolf_mod_tp", Modernization menu).
//
// The standard mod approach (Boondorl's Third-Person-Camera, the wiki
// tutorial) assigns players[consoleplayer].camera from an actor that
// only exists on the local node - fine for single player, but this
// project is lockstep multiplayer first, so camera state follows the
// same rule as everything else: derive it identically on EVERY node
// from replicated data. wolf_mod_tp is a replicated user cvar (the
// wolf_skin pattern), each node spawns a cam for every player who has
// it on, and each player's camera points at their own cam. The
// renderer only consults the local player's camera; the others are a
// few dormant NOINTERACTION actors.
//
// The engine gives us the two hard parts free once player.camera is
// not the pawn: the player's own body renders (the 8-rotation MP skin
// exists for exactly this) and the first-person weapon overlay is
// suppressed.
//
// Interplay learned from this codebase, not guessed:
//   - The boss DeathCam repositions the PAWN (victoryFlag) rather than
//     switching player.camera, so third person must stand down while
//     victoryFlag is set or the chase cam would film the camera stand.
//   - Death: the corpse/respawn flow expects the engine's own view
//     handling; stand down at health <= 0.
//   - Camera maintenance lives in WolfPlayer.Tick AFTER the
//     CF_PREDICTING guard: it writes player.camera (shared sim state).

class WolfChaseCam : Actor
{
    const CAM_DIST = 96.0;      // behind the player, map units
    const CAM_LIFT = 24.0;      // above eye height
    const CAM_PAD  = 6.0;       // stand-off from any wall the trace hits

    Default
    {
        +NOBLOCKMAP
        +NOINTERACTION
        +NOGRAVITY
        +NOTONAUTOMAP
        +DONTSPLASH
        RenderStyle "None";
    }

    override void Tick()
    {
        // No Super.Tick(): this actor simulates nothing. Its position
        // is a pure function of its player's state, recomputed here.
        PlayerPawn p = PlayerPawn(master);
        if (p == null || p.player == null || p.player.mo != p)
        {
            Destroy();
            return;
        }
        double eyez = p.pos.z + p.height * 0.75;
        // Pull in off level geometry: trace horizontally from the eye
        // backwards (the lift above eye level is small enough that the
        // ceiling clamp below covers it). TRF_THRUACTORS so other
        // players/enemies never shove the camera; walls only.
        FLineTraceData t;
        double dist = CAM_DIST;
        if (p.LineTrace(p.angle + 180, CAM_DIST + CAM_PAD, 0,
                        TRF_THRUACTORS | TRF_ABSOFFSET,
                        eyez - p.pos.z, data: t)
            && t.HitType != TRACE_HitNone)
            dist = max(8, t.Distance - CAM_PAD);

        Vector3 want = p.Vec3Offset(
            cos(p.angle + 180) * dist,
            sin(p.angle + 180) * dist,
            (eyez - p.pos.z) + CAM_LIFT);
        // SetOrigin(..., true) keeps render interpolation, so the view
        // glides at any framerate even though this runs per tic.
        SetOrigin(want, true);
        // clamp into the sector's vertical space
        if (pos.z > ceilingz - 4) SetZ(ceilingz - 4);
        if (pos.z < floorz + 4) SetZ(floorz + 4);
        angle = p.angle;
        // look mildly down at the player; follow freelook pitch when on
        pitch = clamp(p.pitch + 10, -80, 80);
    }
}
