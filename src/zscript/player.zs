// WolfPlayer — Phase 1 bootstrap player.
//
// Charter (checklist §3): camera height is CONSTANT at half wall height —
// Wolf renders the eye at the tile midplane, i.e. 32 of our 64-unit walls —
// and there is no view bob and no weapon bob (MOVE-00x family; the
// Modernization menu later re-exposes bob as an OFF-default toggle).
//
// Doom fist/pistol are TEMPORARY placeholders until the Phase 2 weapon set
// (knife/pistol/machine gun/chaingun with WEAP-001..005 cadences) lands.
class WolfPlayer : DoomPlayer
{
    // Movement constants, converted per the charter's zero-rounding policy.
    // Wolf global units: 0x10000/tile; our scale 64 units/tile -> divide 1024.
    // Per engine tic = 2 Wolf tics (TIC-001).
    //   walk fwd/strafe: BASEMOVE(35) * MOVESCALE(150) * 2 / 1024   (MOVE-001/002)
    //   run:             RUNMOVE(70)  * MOVESCALE(150) * 2 / 1024
    //   backpedal uses BACKMOVESCALE(100): slower going backward.
    // Wolf adds the forward and strafe thrusts vectorially with NO
    // normalization — diagonals are faster, as in the original.
    const WALKMOVE = 10500.0 / 1024.0;   // 10.2539...
    const RUNMOVE  = 21000.0 / 1024.0;   // 20.5078...
    const BACKSCALE = 100.0 / 150.0;

    Default
    {
        Player.ViewHeight 32;
        Height 56;
        Player.ViewBob 0;       // no view bob, no weapon bob (1992 default)
        // Wolf loadout: knife + pistol, STARTAMMO 8 (WL_DEF.H:140)
        Player.StartItem "WolfPistol";
        Player.StartItem "WolfKnife";
        Player.StartItem "WolfAmmo", 8;
    }

    // Wolf has ZERO inertia: no acceleration ramp, no glide — velocity is
    // rebuilt from held input every tic and dropped to zero the moment keys
    // are released (ControlMovement/Thrust, WL_AGENT.C). Replaces Doom's
    // momentum physics wholesale.
    override void MovePlayer()
    {
        UserCmd cmd = player.cmd;

        // turning (mouse yaw and keyboard turn arrive premerged in cmd.yaw)
        if (reactiontime)
        {
            reactiontime--;
        }
        else
        {
            Angle += cmd.yaw * (360.0 / 65536.0);
        }

        bool running = (cmd.buttons & BT_SPEED);
        double base = running ? RUNMOVE : WALKMOVE;

        double fwd = 0;
        if (cmd.forwardmove > 0)      fwd = base;
        else if (cmd.forwardmove < 0) fwd = -base * BACKSCALE;
        double side = 0;
        if (cmd.sidemove > 0)         side = base;
        else if (cmd.sidemove < 0)    side = -base;

        Vel.XY = (0, 0);
        if (fwd != 0)  Vel.XY += AngleToVector(Angle, fwd);
        if (side != 0) Vel.XY += AngleToVector(Angle - 90, side);

        // thrustspeed bookkeeping for enemy accuracy (ECOMBAT-003: player
        // counts as "running" when thrust >= RUNSPEED 6000 global/Wolf-tic;
        // walk thrust is 5250, run 10500). Exposed for the Phase 2 sim.
        bIsRunning = running && (fwd != 0 || side != 0);

        if (fwd != 0 || side != 0)
        {
            if (player.playerstate == PST_LIVE)
                PlayRunning();
        }
    }

    bool bIsRunning;
    int oldButtons;
    bool exiting;

    // --- death sequence (Died, WL_GAME.C:1114-1225) ---
    int deathPhase;         // 0 alive, 1 rotating, 2 fizzling, 3 done
    int deathTimer;
    Actor killerActor;

    const DEATHROTATE = 2;  // angle units per Wolf tic (x2 per engine tic)

    override void Die(Actor source, Actor inflictor, int dmgflags,
                      Name MeansOfDeath)
    {
        Super.Die(source, inflictor, dmgflags, MeansOfDeath);
        killerActor = source;
        deathPhase = 1;
        deathTimer = 0;
        A_StartSound("wolf/playerdeath", CHAN_VOICE);
        // gamestate.weapon = -1: the weapon is taken away immediately
        if (player != null)
        {
            player.ReadyWeapon = null;
            player.PendingWeapon = WP_NOCHANGE;
        }
    }

    // Wolf's death has no view drop and no press-use-to-respawn: the view
    // swings to the killer, then the screen dissolves to red.
    override void DeathThink()
    {
        if (player == null)
            return;
        player.Uncrouch();
        ViewHeight = 32;            // camera stays at eye level

        if (deathPhase == 1)
        {
            bool aligned = true;
            if (killerActor != null)
            {
                double want = AngleTo(killerActor);
                double diff = deltaangle(Angle, want);
                double step = DEATHROTATE * 2;      // 2 Wolf tics
                if (abs(diff) > step)
                {
                    Angle += diff > 0 ? step : -step;
                    aligned = false;
                }
                else
                    Angle = want;
            }
            if (aligned)
            {
                deathPhase = 2;
                deathTimer = 0;
                WolfDeathHandler dh = WolfDeathHandler.Get();
                if (dh != null)
                    dh.Begin();
            }
            return;
        }

        if (deathPhase == 2)
        {
            deathTimer++;
            if (deathTimer >= 35 + 40)      // dissolve + IN_UserInput pause
            {
                deathPhase = 3;
                RestartFloor();
            }
        }
    }

    // lives--, then restart the floor with the pistol loadout and the
    // score rolled back to its level-entry value (DEATH-003/004/005).
    void RestartFloor()
    {
        WolfGameState gs = WolfGameState.Get();
        WolfDeathHandler dh = WolfDeathHandler.Get();
        if (dh != null)
            dh.Finish();
        if (gs != null)
        {
            gs.lives--;
            gs.deathRestart = true;
            if (gs.lives < 0)
            {
                // TODO: game over -> menu/high scores. Until that flow
                // exists, start a fresh run on the same floor.
                gs.lives = 3;
                gs.score = 0;
                gs.oldScore = 0;
                gs.nextExtra = WolfGameState.EXTRAPOINTS;
            }
        }
        // no tally when you die (the source goes straight back in)
        Level.ChangeLevel(Level.MapName, 0,
                          CHANGELEVEL_RESETINVENTORY
                          | CHANGELEVEL_NOINTERMISSION, -1);
    }

    // UpdateFace (WL_AGENT.C:307-323): runs in play scope so the look
    // timer consumes the US_RndT stream exactly like the original.
    int faceFrame;
    int faceCount;
    int grinCount;

    void UpdateFace()
    {
        WolfLevel wl = WolfLevel.Get();
        if (wl == null)
            return;
        if (grinCount > 0)
        {
            grinCount -= 2;
            return;
        }
        faceCount += 2;
        if (faceCount > wl.RndT())
        {
            faceFrame = wl.RndT() >> 6;
            if (faceFrame == 3)
                faceFrame = 1;
            faceCount = 0;
        }
    }

    // Cmd_Use (WL_AGENT.C:1008-1080): on use press, scan exactly one tile in
    // the facing cardinal direction (octant test, EXIT-001) and operate any
    // door there. Pushwalls and the elevator switch join in later passes.
    override void Tick()
    {
        Super.Tick();
        // No vertical aim in Wolf (checklist section 3). Enforced here so a
        // stale config can't reintroduce it; the Modernization toggle
        // (wolf_freelook) is the sanctioned way to turn it on later.
        if (player != null)
        {
            CVar fl = CVar.GetCVar("wolf_freelook", player);
            if (fl == null || !fl.GetInt())
                Pitch = 0;
        }
        if (deathPhase != 0)
            return;
        if (player && (player.cmd.buttons & BT_USE)
            && !(oldButtons & BT_USE))
        {
            WolfUse();
        }
        if (player)
            oldButtons = player.cmd.buttons;
        UpdateFace();
    }

    void WolfUse()
    {
        double a = Angle % 360.0;
        if (a < 0) a += 360.0;
        int tx = int(pos.x) / 64;
        int ty = 63 - (int(pos.y) / 64);
        int cx = tx, cy = ty;
        int dir;                                        // 0=E 1=N 2=W 3=S
        if (a < 45.0 || a >= 315.0)      { cx++; dir = 0; }
        else if (a < 135.0)              { cy--; dir = 1; }
        else if (a < 225.0)              { cx--; dir = 2; }
        else                             { cy++; dir = 3; }

        ThinkerIterator it = ThinkerIterator.Create("WolfDoor");
        WolfDoor d;
        while ((d = WolfDoor(it.Next())) != null)
        {
            if (d.tileX == cx && d.tileY == cy)
            {
                d.Operate(self);
                return;
            }
        }
        // elevator switch (Cmd_Use, WL_AGENT.C:1056-1070). EXIT-002: only
        // works facing east or west. EXIT-004: standing on floor code 107
        // (area 0, ALTELEVATORTILE) takes the secret exit instead.
        WolfLevel wl = WolfLevel.Get();
        if (wl != null && wl.ElevatorAt(cx, cy) && (dir == 0 || dir == 2)
            && !exiting)
        {
            exiting = true;
            wl.FlipSwitch(cx, cy);
            A_StartSound("wolf/leveldone", CHAN_VOICE);
            bool secret = wl.AreaAt(tx, ty) == 0;
            if (secret)
                Level.SecretExitLevel(0);
            else
                Level.ExitLevel(0, false);
            return;
        }

        ThinkerIterator pit = ThinkerIterator.Create("WolfPushwall");
        WolfPushwall p;
        while ((p = WolfPushwall(pit.Next())) != null)
        {
            if (p.tileX == cx && p.tileY == cy && p.state_ == 0)
            {
                p.Push(dir, self);
                return;
            }
        }
    }
}
