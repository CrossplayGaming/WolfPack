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

// FREE ORBIT, ported from Crystal Caves (tools/voxel handoff, §6) with
// the one change this project's rules demand: CCFPS keeps the orbit in
// LOCAL-NODE fields because it is single player. Here the camera is
// shared sim state, so the orbit follows the wolf_skin rule instead of
// being gated to single player - state is per player, and every node
// derives all of it from replicated input.
//
// The bridge, documented rather than guessed: InputProcess sees
// Type_Mouse deltas BEFORE the view turns, and returning true consumes
// them - but InputProcess is UI CONTEXT and may not write play fields.
// So deltas accumulate in ui fields, flush once per tic through
// SendNetworkEvent (which every node receives, in order), and land in
// play state in NetworkProcess keyed by the SENDER. One tic of camera
// latency, and lockstep-correct.
//
// The HELD state needs no such ceremony: +user1 arrives in the
// replicated ticcmd (BT_USER1), so every node already knows who is
// orbiting. That also means a release swallowed by an open menu cannot
// wedge the orbit on.
class WolfOrbit : EventHandler
{
    double oyaw[MAXPLAYERS];    // degrees off the at-rest camera yaw
    double opitch[MAXPLAYERS];
    ui int pendX;               // local raw deltas, accumulated per tic
    ui int pendY;

    clearscope static WolfOrbit Get()
    {
        return WolfOrbit(EventHandler.Find("WolfOrbit"));
    }

    // orbiting requires the key held AND that player actually being in
    // third person - otherwise the mouse must keep turning the view
    clearscope static bool OrbitHeld(int pn)
    {
        if (pn < 0 || !playeringame[pn])
            return false;
        PlayerInfo pi = players[pn];
        if (pi == null || pi.mo == null || !(pi.cmd.buttons & BT_USER1))
            return false;
        CVar cv = CVar.GetCVar("wolf_mod_tp", pi);
        return cv != null && cv.GetInt() != 0;
    }

    override bool InputProcess(InputEvent e)
    {
        if (e.Type != InputEvent.Type_Mouse || !OrbitHeld(consoleplayer))
            return false;
        pendX += e.MouseX;
        pendY += e.MouseY;
        return true;            // eaten: the player's own view must not turn
    }

    override void UiTick()
    {
        if (pendX != 0 || pendY != 0)
        {
            SendNetworkEvent("wolf_orbit", pendX, pendY);
            pendX = 0;
            pendY = 0;
        }
    }

    override void NetworkProcess(ConsoleEvent e)
    {
        if (!(e.Name ~== "wolf_orbit"))
            return;
        int pn = e.Player;
        if (pn < 0 || pn >= MAXPLAYERS || !playeringame[pn])
            return;
        // read the SENDER's cvars, not the local player's: in a netgame
        // this event is processed on every node
        PlayerInfo pi = players[pn];
        CVar sens = CVar.GetCVar("wolf_tp_orbsens", pi);
        // rides on top of the user's mouse sensitivity - InputProcess
        // deltas arrive pre-scaled
        double k = sens ? sens.GetFloat() : 0.2;
        CVar ix = CVar.GetCVar("wolf_tp_orbinvx", pi);
        CVar iy = CVar.GetCVar("wolf_tp_orbinvy", pi);
        double sx = (ix && ix.GetInt() != 0) ? -1 : 1;
        double sy = (iy && iy.GetInt() != 0) ? -1 : 1;
        oyaw[pn] -= e.Args[0] * k * sx;
        opitch[pn] = clamp(opitch[pn] - e.Args[1] * k * sy, -80, 80);
    }

    override void WorldTick()
    {
        for (int pn = 0; pn < MAXPLAYERS; pn++)
        {
            if (OrbitHeld(pn))
                continue;
            // glide back behind the player on release (and whenever
            // third person stands down, so death or a boss cutscene
            // never hands the view back swung sideways)
            oyaw[pn] *= 0.85;
            opitch[pn] *= 0.85;
            if (abs(oyaw[pn]) < 0.5) oyaw[pn] = 0;
            if (abs(opitch[pn]) < 0.5) opitch[pn] = 0;
        }
    }
}

class WolfChaseCam : Actor
{
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

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        // The renderer clamps its viewpoint inside the camera sector's
        // floor/ceiling planes (R_SetupFrame: ceilingplane - 4) - a
        // GEOMETRY clamp, so the open-roof sky texture never freed the
        // camera (measured: sim camera at z=335 rendered from z=60
        // under the 64 ceiling; owner called it: "a limitation of the
        // level geometry forcing the camera not to move past it").
        // VPSF_ALLOWOUTOFBOUNDS is the engine's own escape hatch for
        // exactly this (hardware renderer only): a ViewPos with the
        // flag and zero offset renders from the actor's true position.
        SetViewPos((0, 0, 0), VPSF_ALLOWOUTOFBOUNDS);
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
        // framing comes from THIS player's replicated cvars, so every
        // node places this player's camera identically
        double dist = CVarF(p, "wolf_tp_dist", 96);
        double lift = CVarF(p, "wolf_tp_lift", 24);

        double oy = 0, op = 0;
        let h = WolfOrbit.Get();
        if (h != null)
        {
            int pn = p.PlayerNumber();
            if (pn >= 0) { oy = h.oyaw[pn]; op = h.opitch[pn]; }
        }

        // Spherical placement around the eye. The at-rest point sits
        // exactly `dist` behind and `lift` above the eye - so the
        // Height slider truly RAISES the camera. (The first version
        // used dist alone as the radius, which turned Height into a
        // tilt-only knob: cranking it steepened a close camera toward
        // top-down and read as "still blocked by the ceiling" - owner
        // repro with the roof already open.) The orbit swings that
        // same sphere.
        // p.pitch joins the ELEVATION, mirroring how p.angle drives the
        // yaw: mouse-vertical moves the camera along the sphere (look
        // down -> camera swings overhead, look up -> it drops low), and
        // the aim below stays locked on the player. The first version
        // added p.pitch to the AIM instead, which tilted the view off
        // him - horizontal mouse kept him centered (position follows
        // p.angle) but vertical mouse did not (owner repro, both orbit
        // and rest).
        double yaw = p.angle + 180 + oy;
        double elRest = atan2(lift, dist);
        double el = clamp(elRest + op + p.pitch, -85, 85);
        double radius = sqrt(dist * dist + lift * lift);
        // Overhead gain: a FIXED-radius sphere tops out barely two
        // wall-heights up, and swinging overhead brings the player's
        // head much nearer the lens than his eye - he balloons in
        // frame and it reads as the camera diving in (owner: "pushed
        // or pulled in close when I move it above BJ"). Tilting above
        // the at-rest elevation therefore spirals the camera OUT as
        // it rises - up to 2.5x radius straight overhead, the real
        // dollhouse view. Below rest nothing changes: floors and
        // walls stay solid and the wall pull-in still owns that zone.
        if (el > elRest)
        {
            double t = (el - elRest) / max(1, 85 - elRest);
            radius *= 1 + 1.5 * t * t;
        }

        // Pull in off level geometry: trace from the eye along the ACTUAL
        // 3D camera direction (negative LineTrace pitch = up), not just
        // horizontally - once the camera can swing overhead, a horizontal
        // trace stops describing where it is going. TRF_THRUACTORS so
        // other players and enemies never shove the camera; walls only.
        // Open-roof rule first: if the camera's DESTINATION is in the
        // sky above the map, it is in open air - no wall can truly be
        // between it and the roofless room below, even though a
        // straight trace to it clips wall segments on the way (one-
        // sided lines block Doom traces at ANY height, so the trace
        // cannot distinguish "through a wall" from "over it").
        TextureID skyTex = TexMan.CheckForTexture("F_SKY1",
                                                  TexMan.Type_Flat);
        let sk = WolfSkyCeil.Get();
        bool roofOpen = sk != null && sk.skyOn;
        double wantZ = eyez + sin(el) * radius;
        // p.ceilingz = the actor's cached ceiling height (sectors
        // expose no plain ceilingz field - engine parse error)
        bool freeAir = roofOpen && wantZ > p.ceilingz + 8;

        FLineTraceData t;
        bool hit = !freeAir
            && p.LineTrace(yaw, radius + CAM_PAD, -el,
                        TRF_THRUACTORS | TRF_ABSOFFSET,
                        eyez - p.pos.z, data: t)
            && t.HitType != TRACE_HitNone;
        // a sky ceiling is a window, not a wall
        if (hit && t.HitType == TRACE_HitCeiling && t.HitSector != null
            && t.HitSector.GetTexture(Sector.ceiling) == skyTex)
            hit = false;
        if (hit)
            radius = max(8, t.Distance - CAM_PAD);

        Vector3 want = p.Vec3Offset(
            cos(yaw) * cos(el) * radius,
            sin(yaw) * cos(el) * radius,
            (eyez - p.pos.z) + sin(el) * radius);
        // SetOrigin(..., true) keeps render interpolation, so the view
        // glides at any framerate even though this runs per tic.
        SetOrigin(want, true);
        // clamp into the sector's vertical space
        // the ceiling clamp stands down while the roof is open
        if (CurSector.GetTexture(Sector.ceiling)
            != TexMan.CheckForTexture("F_SKY1", TexMan.Type_Flat)
            && pos.z > ceilingz - 4)
            SetZ(ceilingz - 4);
        if (pos.z < floorz + 4) SetZ(floorz + 4);
        // Look AT the player - closed-loop, from the camera's FINAL
        // position. The first version assumed pitch = elevation angle,
        // which only aims at him while the camera sits exactly on the
        // ideal sphere; after a wall pull-in or a floor/ceiling clamp
        // the assumed angle drifts off target (owner: "BJ doesn't seem
        // to be the center of the sphere"). Computing pitch from the
        // actual camera->eye vector holds him centered no matter what
        // moved the camera. p.pitch is already in the elevation above,
        // so it must NOT tilt the aim too.
        Vector3 toEye = p.Vec3Offset(0, 0, eyez - p.pos.z) - pos;
        angle = yaw + 180;
        double horiz = toEye.xy.Length();
        double aim = horiz > 1 ? atan2(-toEye.z, horiz) : el;
        // The renderer maps view pitch through the world's vertical
        // pixel stretch (Doom's 1.2 non-square pixels): displayed
        // pitch = atan(stretch * tan(assigned)). Near horizontal the
        // difference vanishes, but at orbit-overhead angles it
        // AMPLIFIES the pitch and pushes the player off frame center
        // (measured: aim 57.8 assigned, he rendered ~a head above the
        // crosshair; the mirror error looking up). Assign the inverse
        // so the DISPLAYED center lands on him.
        CVar dbg = CVar.FindCVar("wolf_dbg_check");
        pitch = clamp(atan(tan(clamp(aim, -85, 85))
                          / Level.pixelstretch), -85, 85);
        if (dbg != null && dbg.GetInt() != 0 && Level.maptime % 30 == 0)
            Console.Printf("CAMDBG cam=(%.0f,%.0f,%.0f) eye_z=%.0f "
                           "toEye=(%.0f,%.0f,%.0f) aim=%.1f ppitch=%.1f "
                           "el=%.1f R=%.0f freeAir=%d",
                           pos.x, pos.y, pos.z, eyez,
                           toEye.x, toEye.y, toEye.z, aim, p.pitch, el,
                           radius, freeAir);
    }

    // per-player (replicated) float, with the default if it is missing
    static double CVarF(PlayerPawn p, String name, double dflt)
    {
        CVar cv = CVar.GetCVar(name, p.player);
        return cv ? cv.GetFloat() : dflt;
    }
}


// The engine draws the crosshair only when the view camera IS the
// player pawn - in third person there is none (measured: first-person
// shot has the circle, chasecam shot does not). This overlay fills the
// gap with the same lump, scale and color the engine would use, so
// toggling views never changes the crosshair's look.
class WolfChaseXhair : EventHandler
{
    override void RenderOverlay(RenderEvent e)
    {
        PlayerInfo p = players[consoleplayer];
        if (p == null || p.mo == null || !(p.camera is "WolfChaseCam"))
            return;
        // CAMDBG ground truth: what the RENDERER actually used this
        // frame vs what the sim assigned - ends the guessing about
        // where the view is aimed. Debug-gated, probe only.
        CVar dbgc = CVar.FindCVar("wolf_dbg_check");
        if (dbgc != null && dbgc.GetInt() != 0)
        {
            String s = String.Format(
                "RENDER vp=(%.0f,%.0f,%.0f) pitch=%.1f ang=%.1f | "
                "SIM cam=(%.0f,%.0f,%.0f) pitch=%.1f ang=%.1f",
                e.ViewPos.x, e.ViewPos.y, e.ViewPos.z,
                e.ViewPitch, e.ViewAngle,
                p.camera.pos.x, p.camera.pos.y, p.camera.pos.z,
                p.camera.pitch, p.camera.angle);
            Screen.DrawText(smallfont, Font.CR_GOLD, 8,
                Screen.GetHeight() / 2, s, DTA_ScaleX, 2.0,
                DTA_ScaleY, 2.0);
        }
        // A center-screen reticle only tells the truth while the camera
        // looks down the player's own facing. Once the orbit swings off
        // rest it would aim at whatever happens to be under the middle
        // of a sideways view, so drop it until the camera glides back.
        let orb = WolfOrbit.Get();
        if (orb != null && (abs(orb.oyaw[consoleplayer]) > 0.5
                            || abs(orb.opitch[consoleplayer]) > 0.5))
            return;
        CVar on = CVar.FindCVar("crosshairon");
        if (on == null || on.GetInt() == 0)
            return;
        CVar st = CVar.FindCVar("crosshair");
        int style = st == null ? 0 : clamp(st.GetInt(), 0, 7);
        if (style == 0)
            style = 1;              // "Default" resolves native-side; use Cross 1
        TextureID t = TexMan.CheckForTexture(
            String.Format("XHAIRS%d", style), TexMan.Type_MiscPatch);
        if (!t.IsValid())
            return;

        // color: health tint when crosshairhealth is on (the engine's
        // green->yellow->red ramp, approximated), else crosshaircolor
        Color col;
        CVar hc = CVar.FindCVar("crosshairhealth");
        if (hc != null && hc.GetInt() != 0)
        {
            int h = clamp(p.mo.health, 0, 100);
            col = Color(clamp((100 - h) * 255 / 50, 0, 255),
                        clamp(h * 255 / 50, 0, 255), 0);
        }
        else
        {
            CVar cc = CVar.FindCVar("crosshaircolor");
            col = cc == null ? Color(255, 255, 255) : Color(cc.GetInt());
        }

        CVar sc = CVar.FindCVar("crosshairscale");
        double k = sc == null ? 1.0 : clamp(sc.GetFloat(), 0.0, 2.0);
        int vx, vy, vw, vh;
        [vx, vy, vw, vh] = Screen.GetViewWindow();
        int tw, th;
        [tw, th] = TexMan.GetSize(t);
        // the engine sizes crosshairs by INTEGER clean-scale steps of
        // the full screen height (not fractional view height - measured
        // as a slightly smaller ring in the first A/B); match exactly
        // so toggling views never changes the crosshair size
        double f = k * max(1, int(Screen.GetHeight() / 200));
        Screen.DrawTexture(t, false,
            vx + vw / 2 - tw * f / 2, vy + vh / 2 - th * f / 2,
            DTA_DestWidthF, tw * f, DTA_DestHeightF, th * f,
            DTA_FillColor, col & 0xFFFFFF,
            DTA_AlphaChannel, true);    // XHAIRS are alpha-only images:
                                        // FillColor without this paints
                                        // the whole rect (measured: a
                                        // gold square, not a circle)
    }
}
