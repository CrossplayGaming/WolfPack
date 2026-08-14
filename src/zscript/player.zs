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

    // Netgame body (the generated BJ set, grey variant). Single-player
    // never renders the player; without these, other players draw as
    // the missing-sprite marker.
    // User-painted BJ set (import_bj_sheet.py), guard frame layout plus
    // the ROTATED fire frames - a deliberate extension: a player's shots
    // must read from any angle (the original's enemies always face
    // their target, so its attack frames never rotated).
    States
    {
    Spawn:
        BJ1S A -1;
        Loop;
    See:
        BJ1W ABCD 4;
        Loop;
    Missile:
        BJ1F A 10;
        Goto Spawn;
    Pain:
        BJ1P A 5;
        BJ1P B 5;
        Goto Spawn;
    Death:
        BJ1D ABC 8;
        BJ1D D -1;
        Stop;
    // sprite-name registration only - never entered. The BJ2-4 uniform
    // recolors (Player Setup) swap in by sprite ID at Tick time; without
    // a States mention their names never register and GetSpriteIndex
    // returns -1 (playbook 4).
    SkinReg:
        BJ1A ABC -1;
        BJ2S A -1; BJ2W ABCD -1; BJ2F A -1;
        BJ2P AB -1; BJ2A ABC -1; BJ2D ABCD -1;
        BJ3S A -1; BJ3W ABCD -1; BJ3F A -1;
        BJ3P AB -1; BJ3A ABC -1; BJ3D ABCD -1;
        BJ4S A -1; BJ4W ABCD -1; BJ4F A -1;
        BJ4P AB -1; BJ4A ABC -1; BJ4D ABCD -1;
        Stop;
    }

    // Wolf has ZERO inertia: no acceleration ramp, no glide — velocity is
    // rebuilt from held input every tic and dropped to zero the moment keys
    // are released (ControlMovement/Thrust, WL_AGENT.C). Replaces Doom's
    // momentum physics wholesale.
    override void MovePlayer()
    {
        UserCmd cmd = player.cmd;

        // the stock MovePlayer computes this as a side effect; dropping it
        // in the override left onground permanently false, which silently
        // vetoed the engine's CheckJump (engine player.zs:1299)
        player.onground = (pos.z <= floorz) || bOnMobj
                          || (player.cheats & CF_NOCLIP2);

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
        // enemy accuracy reads this (ECOMBAT-003) - a prediction re-run
        // must not contaminate it, or each node's enemies roll different
        // hit chances and the lockstep diverges (the co-op desync: DM
        // strips enemies, so only co-op sessions ever saw it)
        if (player == null || !(player.cheats & CF_PREDICTING))
            bIsRunning = running && (fwd != 0 || side != 0);

        // animation transitions mirror the engine's own guards: never
        // from prediction re-runs, and the return to the standing frame
        // is explicit - the engine's CheckStopped lives on a movement
        // path the zero-inertia override bypasses (user repro: netgame
        // bodies stuck in the walk loop after stopping)
        if (player.cheats & CF_PREDICTING)
            return;
        if (fwd != 0 || side != 0)
        {
            if (player.playerstate == PST_LIVE)
                PlayRunning();
        }
        else if (player.playerstate == PST_LIVE)
            PlayIdle();
    }

    // ---- uniform color (Player Setup) -----------------------------------
    // wolf_skin is userinfo: per-player, replicated, archived. The state
    // machine always sets the BJ1 (grey) sprites; this remaps them to the
    // chosen recolor right after Tick advanced the state, so the renderer
    // never sees the grey frame. Lockstep-safe: every node reads the same
    // replicated value and computes the same remap.
    static const name SKINBASE[] = { 'BJ1S', 'BJ1W', 'BJ1F',
                                     'BJ1P', 'BJ1A', 'BJ1D' };
    static const name SKINVAR[] = { 'BJ2S', 'BJ2W', 'BJ2F',
                                    'BJ2P', 'BJ2A', 'BJ2D',
                                    'BJ3S', 'BJ3W', 'BJ3F',
                                    'BJ3P', 'BJ3A', 'BJ3D',
                                    'BJ4S', 'BJ4W', 'BJ4F',
                                    'BJ4P', 'BJ4A', 'BJ4D' };
    // identifiers are case-insensitive, so these can't share the
    // constant arrays' names
    int sprGrey[6];
    int sprTint[18];
    bool skinInit;

    void InitSkinTable()
    {
        if (skinInit)
            return;
        for (int k = 0; k < 6; k++)
        {
            sprGrey[k] = GetSpriteIndex(SKINBASE[k]);
            for (int vi = 0; vi < 3; vi++)
                sprTint[vi * 6 + k] = GetSpriteIndex(SKINVAR[vi * 6 + k]);
        }
        skinInit = true;
    }

    int SkinVariant()
    {
        CVar cv = CVar.GetCVar("wolf_skin", player);
        return cv == null ? 0 : clamp(cv.GetInt(), 0, 3);
    }

    // sprite id for one of the six kinds under the chosen uniform
    int SkinSprite(int kind)
    {
        InitSkinTable();
        int v = SkinVariant();
        return v == 0 ? sprGrey[kind] : sprTint[(v - 1) * 6 + kind];
    }

    void ApplySkin()
    {
        if (player == null)
            return;
        int v = SkinVariant();
        if (v == 0)
            return;
        InitSkinTable();
        for (int k = 0; k < 6; k++)
        {
            if (sprite == sprGrey[k])
            {
                int id = sprTint[(v - 1) * 6 + k];
                if (id > 0)
                    sprite = id;
                return;
            }
        }
    }

    // ---- voxel body (optional pack) -------------------------------------
    // See voxelbody.zs: the KVX sets carry longer cycles than the sprite
    // states, and those extra frames cannot be named in the States block
    // because the pack is an optional download and a state naming a
    // missing frame is a load error. So drive sprite+frame directly -
    // the renderer resolves the voxel at draw time, not at compile time.
    int voxTic;
    int voxKind;        // 0 none, 1 idle, 2 run, 3 shoot, 4 death, 5 pain
    int fireHold;       // aim-pose hysteresis after the last shot
    Actor gunBody;
    bool voxChecked, voxOn;

    void ApplyVoxelBody()
    {
        if (player == null)
            return;
        if (!voxChecked)
        {
            voxChecked = true;
            voxOn = WolfVoxBody.Present();
        }
        if (!voxOn)
            return;
        // The gun is a separate actor and it lives in the PACK, not
        // here, because its sprite frames only exist there. Look the
        // class up by name so a plain build simply finds nothing.
        if (gunBody == null && health > 0)
        {
            // a class literal is resolved at COMPILE time, and the
            // pack's classes are not visible to the base game's
            // compilation unit ("Unknown class name 'WolfGunBody'").
            // Casting from a Name VARIABLE defers it to runtime, which
            // is what an optional add-on requires.
            Name gn = 'WolfGunBody';
            class<Actor> gc = (class<Actor>)(gn);
            if (gc != null)
            {
                gunBody = Spawn(gc, pos);
                if (gunBody != null)
                    gunBody.master = self;
            }
        }

        // Kinds: 1 idle, 2 walk fwd, 3 walk BACK, 4 death, 5 pain,
        // 6 fire fwd, 7 fire back, 8 stab. Direction comes from
        // replicated state (this game rebuilds vel from held input
        // every tic), so every node picks the same cycle.
        bool inMissile = InStateSequence(CurState, ResolveState("Missile"));
        Vector2 fwdv = AngleToVector(angle);
        bool movingBack = (vel.xy dot fwdv) < -0.1;

        int kind = 0;
        if (InStateSequence(CurState, ResolveState("Death")))
            kind = 4;
        else if (inMissile)
            kind = 6;
        else if (InStateSequence(CurState, ResolveState("See")))
            kind = movingBack ? 3 : 2;
        else if (InStateSequence(CurState, ResolveState("Pain")))
            kind = 5;      // frames left to the state: two poses, two frames
        else if (InStateSequence(CurState, ResolveState("Spawn")))
            kind = 1;

        // HELD FIRE. The pawn's Missile state is a one-shot: it runs ten
        // tics and returns to Spawn, which is right for the pistol
        // (Cmd_Fire is edge-triggered, WEAPON.NOAUTOFIRE) and wrong for
        // anything that keeps firing while the button is down - BJ
        // twitched into the firing pose and dropped straight out of it
        // mid-burst. Keyed on the weapon's own declaration rather than a
        // list of class names, so a future bazooka behaves per its flag.
        bool sustained = player.ReadyWeapon != null
            && !player.ReadyWeapon.bNoAutofire
            && (player.cmd.buttons & BT_ATTACK) != 0;
        bool firing = sustained || inMissile;
        if (firing && kind != 4 && kind != 5)
        {
            // Firing states are per WEAPON: pistol and long gun each
            // have a directional walk-fire pair, the knife has its
            // stab. Standing still fires the forward cycle - its first
            // strides read fine in place.
            int wep = VoxWeapon();
            if (wep == 3)
                kind = 8;
            else
                kind = movingBack ? 7 : 6;
            fireHold = 18;      // ~0.5 s at the aim before lowering
        }
        else if (fireHold > 0 && (kind == 1 || kind == 2 || kind == 3)
                 && VoxWeapon() != 3)
        {
            // FIRE-POSE HYSTERESIS (owner report: the gun visibly
            // re-seats at every carry<->aim switch, and the pistol -
            // edge-triggered, ten tics per shot - snapped twice per
            // trigger pull). Hold the aim for a beat after the last
            // shot: taps merge into one sustained aim, and the re-seat
            // happens once on the way in and once on the way out.
            // Replicated state only (fireHold is a pawn field advanced
            // in Tick), so every node holds identically. The knife is
            // exempt: the stab plays once and holding its final pose
            // would freeze the lunge.
            fireHold--;
            kind = movingBack ? 7 : 6;
        }
        else
            fireHold = 0;
        if (kind == 0)
        {
            voxKind = 0;
            return;
        }
        if (kind == 5)          // pain: the state drives the frame
        {
            voxKind = 5;
            return;
        }
        if (kind != voxKind)
        {
            CVar dbg = CVar.FindCVar("wolf_dbg_check");
            if (dbg != null && dbg.GetInt() != 0)
                Console.Printf("KINDSWAP t=%d %d -> %d",
                               Level.maptime, voxKind, kind);
            voxKind = kind;
            voxTic = 0;
        }
        else
            voxTic++;

        int pose;
        if (kind == 1)
            pose = (voxTic / WolfVoxBody.IDLE_TICS) % WolfVoxBody.IDLE_POSES;
        else if (kind == 2)
            pose = (voxTic / WolfVoxBody.RUN_TICS) % WolfVoxBody.RUN_POSES;
        else if (kind == 3)
        {
            // plain backward walk (BJ?B) - pack-only set, so the sprite
            // is redirected the same way the fire sets are
            pose = (voxTic / WolfVoxBody.BWALK_TICS)
                   % WolfVoxBody.BWALK_POSES;
            int id = PackSprite(4);
            if (id > 0)
                sprite = id;
        }
        else if (kind == 6 || kind == 7)
        {
            // directional walk-fire: pistol G/K, long gun L/M
            bool back = kind == 7;
            int wep = VoxWeapon();
            int poses = wep == 2 ? WolfVoxBody.PFIRE_POSES
                                 : WolfVoxBody.LFIRE_POSES;
            int tics = wep == 2 ? WolfVoxBody.PFIRE_TICS
                                : WolfVoxBody.LFIRE_TICS;
            pose = (voxTic / tics) % poses;
            int id = PackSprite(wep == 2 ? (back ? 1 : 0)
                                         : (back ? 3 : 2));
            if (id > 0)
                sprite = id;
        }
        else if (kind == 8)
        {
            // knife stab: played once, held at the last pose
            pose = min(voxTic / WolfVoxBody.STAB_TICS,
                       WolfVoxBody.STAB_POSES - 1);
            int id = PackSprite(5);
            if (id > 0)
                sprite = id;
        }
        else
        {
            pose = min(voxTic / WolfVoxBody.DEATH_TICS,
                       WolfVoxBody.DEATH_POSES - 1);
        }
        frame = pose;
    }

    // Which weapon the voxel driver should dress him with:
    // 0 none, 1 long gun, 2 pistol, 3 knife.
    int VoxWeapon()
    {
        let w = player.ReadyWeapon;
        if (w == null)
            return 0;
        Name cn = w.GetClassName();
        if (cn == 'WolfPistol')
            return 2;
        if (cn == 'WolfKnife')
            return 3;
        return 1;
    }

    // The directional and stab body sets exist ONLY in the voxel pack -
    // base art has no such frames, so they cannot appear in SkinReg (a
    // state naming a missing frame is a load error for anyone without
    // the pack). The PACK's gun actor registers the names; these
    // lookups run only when the pack is present (voxOn), by which time
    // registration has happened.
    // Table rows: 0 pistol-fwd G, 1 pistol-back K, 2 longgun-fwd L,
    // 3 longgun-back M, 4 walk-back B, 5 stab T; four uniforms each.
    // (identifiers are case-insensitive - same trap as the skin tables -
    // so the cache cannot share the constant array's name)
    static const name PACKSETS[] = {
        'BJ1G', 'BJ2G', 'BJ3G', 'BJ4G',
        'BJ1K', 'BJ2K', 'BJ3K', 'BJ4K',
        'BJ1L', 'BJ2L', 'BJ3L', 'BJ4L',
        'BJ1M', 'BJ2M', 'BJ3M', 'BJ4M',
        'BJ1B', 'BJ2B', 'BJ3B', 'BJ4B',
        'BJ1T', 'BJ2T', 'BJ3T', 'BJ4T' };
    int packSpr[24];
    bool packInit;

    int PackSprite(int row)
    {
        if (!packInit)
        {
            packInit = true;
            for (int i = 0; i < 24; i++)
                packSpr[i] = GetSpriteIndex(PACKSETS[i]);
        }
        return packSpr[row * 4 + SkinVariant()];
    }

    bool bIsRunning;
    int oldButtons;
    bool exiting;
    bool victoryStarted;
    double victoryDestY;

    // palette-shift counters (StartDamageFlash / StartBonusFlash,
    // WL_PLAY.C:1143-1160). Decay by tics each frame.
    int damageCount, bonusCount;

    override int DamageMobj(Actor inflictor, Actor source, int damage,
                            Name mod, int flags, double angle)
    {
        int taken = Super.DamageMobj(inflictor, source, damage, mod, flags,
                                     angle);
        if (taken > 0)
            damageCount += taken;       // FLASH-002: intensity scales
        return taken;
    }

    // --- death sequence (Died, WL_GAME.C:1114-1225) ---
    int deathPhase;         // 0 alive, 1 rotating, 2 fizzling, 3 done
    int deathTimer;
    Actor killerActor;

    const DEATHROTATE = 2;  // angle units per Wolf tic (x2 per engine tic)
    const RESPAWN_WAIT = 70;    // netgame: 2 s cooldown before respawn
    const RESPAWN_AUTO = 175;   // netgame: 5 s auto-respawn

    override void Die(Actor source, Actor inflictor, int dmgflags,
                      Name MeansOfDeath)
    {
        Super.Die(source, inflictor, dmgflags, MeansOfDeath);
        if (netgame)
        {
            // Co-op death (user decision, respawn mode): the engine's
            // native co-op respawn takes over - press use, respawn at a
            // start with the pistol loadout. No fizzle, no floor restart,
            // no score rollback; the floor keeps fighting. One life is
            // spent (floor of 0 keeps late-joiners playable). Host-chosen
            // spectate mode lands with the lobby.
            WolfGameState ngs = WolfGameState.Get();
            if (ngs != null)
            {
                int dpn = PlayerNumber();
                ngs.lives[dpn] = max(0, ngs.lives[dpn] - 1);
            }
            deathTimer = 0;             // respawn cooldown starts now
            // deathmatch convention: the corpse drops its best gun (and
            // a clip) so the victor can claim it. Dropped flag keeps
            // sv_itemrespawn from regenerating corpse drops.
            if (deathmatch)
            {
                String drop = "";
                if (FindInventory("WolfChaingun") != null)
                    drop = "WolfStatic28";
                else if (FindInventory("WolfMachineGun") != null)
                    drop = "WolfStatic27";
                if (drop.Length() > 0)
                {
                    Actor d = Spawn(drop, pos);
                    if (d != null) d.bDropped = true;
                }
                Actor c = Spawn("WolfStatic26", pos + (24, 0, 0));
                if (c != null) c.bDropped = true;
            }
            return;
        }
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
        if (netgame)
        {
            // The Wolf sequence (rotate + fizzle + floor restart) is
            // single-player. Netgame policy (user spec): 2 s cooldown
            // where nothing respawns, then use OR fire respawns, and a
            // 5 s auto-respawn if no button. Spawn placement is the
            // farthest-from-opponents rule set at launch.
            if (player.cheats & CF_PREDICTING)
            {
                // deathTimer is a custom field the prediction backup
                // does not restore - advancing it here desyncs (same
                // class as the Tick RNG divergence)
                Super.DeathThink();
                return;
            }
            deathTimer++;
            if (deathTimer < RESPAWN_WAIT)
                player.cmd.buttons &= ~BT_USE;  // mask engine respawn
            Super.DeathThink();
            if (player.playerstate == PST_DEAD
                && (deathTimer >= RESPAWN_AUTO
                    || (deathTimer >= RESPAWN_WAIT
                        && (player.cmd.buttons & BT_ATTACK))))
                player.playerstate = PST_REBORN;
            return;
        }
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
            if (deathTimer >= 72 + 50)      // 2.05s dissolve + IN_UserInput(100)
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
            int dpn = PlayerNumber();
            gs.lives[dpn]--;
            gs.deathRestart = true;
            gs.skipPsyched = true;
            if (gs.lives[dpn] < 0)
            {
                // TODO: game over -> menu/high scores. Until that flow
                // exists, start a fresh run on the same floor.
                gs.lives[dpn] = 3;
                gs.score[dpn] = 0;
                gs.oldScore[dpn] = 0;
                gs.nextExtra[dpn] = WolfGameState.EXTRAPOINTS;
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
    WolfChaseCam chaseCam;

    // Third person (wolf_mod_tp): camera state is SHARED SIM STATE
    // (player.camera), so this runs on every node for every player,
    // after the CF_PREDICTING guard, from the replicated user cvar -
    // the wolf_skin pattern. The engine renders the pawn's own body
    // and hides the weapon overlay whenever camera != mo.
    void MaintainChaseCam()
    {
        if (player == null)
            return;
        CVar cv = CVar.GetCVar("wolf_mod_tp", player);
        bool wanted = cv != null && cv.GetInt() != 0
            && health > 0 && !victoryStarted;
        // the boss DeathCam repositions the pawn itself (victoryFlag);
        // filming that from behind would show the camera stand
        let gs = WolfGameState.Get();
        if (gs != null && gs.victoryFlag)
            wanted = false;
        if (wanted)
        {
            if (chaseCam == null)
            {
                chaseCam = WolfChaseCam(Spawn("WolfChaseCam", pos));
                if (chaseCam != null)
                    chaseCam.master = self;
            }
            if (chaseCam != null && player.camera != chaseCam)
                player.camera = chaseCam;
        }
        else if (chaseCam != null)
        {
            if (player.camera == chaseCam)
                player.camera = self;
            chaseCam.Destroy();
            chaseCam = null;
        }
    }

    override void Tick()
    {
        Super.Tick();
        // uniform recolor runs even through death: the corpse keeps the
        // chosen color
        ApplySkin();
        // and then the voxel pack's longer cycle, if it is loaded: it
        // only picks the FRAME within the uniform ApplySkin just chose
        ApplyVoxelBody();
        // Netgame client prediction re-runs the local player's Tick
        // several times per frame and restores the PAWN afterward - but
        // not global state. Everything below mutates shared sim state
        // (the US_RndT stream via UpdateFace, doors via WolfUse, level
        // exit via the victory scan), so predicted re-runs advanced the
        // RNG stream on each node unevenly: beacon-proven divergence at
        // the first sample, and kills that only one node computed. Same
        // guard the engine's own player code uses for its side effects.
        if (player != null && (player.cheats & CF_PREDICTING))
            return;
        MaintainChaseCam();
        // Vertical aim is suppressed by MAPINFO's NoFreelook (defaultmap),
        // which is the engine's own clamp. Do NOT also force Pitch here:
        // writing pitch after the input has applied it fights the mouse
        // every frame and makes the view jitter. When the Modernization
        // menu exposes freelook, it lifts the MAPINFO flag instead.
        if (deathPhase != 0)
            return;

        // VictoryTile (WL_AGENT.C:961-962): walking onto a plane-1 code 99
        // tile fires BJ's victory run. Only E1 and E5 have these tiles.
        if (victoryStarted)
        {
            // spin toward south (270) at 3 deg per Wolf tic = 6/engine tic
            double d = deltaangle(Angle, 270);
            if (abs(d) <= 6)      Angle = 270;
            else if (d > 0)       Angle += 6;
            else                  Angle -= 6;
            // glide north at 4096 wolf units per Wolf tic = 8 units
            if (pos.y < victoryDestY)
                SetOrigin((pos.x, min(pos.y + 8, victoryDestY), pos.z),
                          true);
            return;
        }
        if (!victoryStarted)
        {
            int vtx = int(pos.x) / 64, vty = 63 - (int(pos.y) / 64);
            ThinkerIterator vit = ThinkerIterator.Create("WolfVictoryTrigger");
            WolfMarker vm;
            while ((vm = WolfMarker(vit.Next())) != null)
            {
                if (vm.tileX == vtx && vm.tileY == vty)
                {
                    if (netgame)
                    {
                        // co-op: skip the one-camera BJ staging, end the
                        // floor for everyone (user decision)
                        WolfGameState ngs = WolfGameState.Get();
                        if (ngs != null)
                            ngs.victoryFlag = true;
                        Level.ExitLevel(0, false);
                        return;
                    }
                    victoryStarted = true;
                    // VictorySpin (WL_AGENT.C:1255): control is taken,
                    // the weapon lowers, and the player glides 5 tiles
                    // north of the trigger while spinning to face south
                    // to watch BJ come. desty = ((tiley-5)<<16) - 0x3000.
                    victoryDestY = 4096.0 - ((vty - 5) * 64 - 12);
                    player.cheats |= CF_TOTALLYFROZEN;
                    PSprite psp = player.GetPSprite(PSP_WEAPON);
                    if (psp != null)
                        psp.SetState(null);
                    player.ReadyWeapon = null;
                    WolfGameState gs = WolfGameState.Get();
                    if (gs != null)
                        gs.victoryFlag = true;
                    WolfBJVictory bj = WolfBJVictory(Spawn("WolfBJVictory",
                                                           pos));
                    if (bj != null)
                        bj.StartRun(self);
                    break;
                }
            }
        }
        if (player && (player.cmd.buttons & BT_USE)
            && !(oldButtons & BT_USE))
        {
            CVar uv = CVar.FindCVar("wolf_dbg_check");
            if (uv != null && uv.GetInt() != 0)
                Console.Printf("WOLFDBG use-edge fired");
            WolfUse();
        }
        if (player)
            oldButtons = player.cmd.buttons;
        UpdateFace();
        // UpdatePaletteShifts: counters fall by tics (2 per engine tic)
        if (damageCount > 0)
            damageCount = max(0, damageCount - 2);
        if (bonusCount > 0)
            bonusCount = max(0, bonusCount - 2);
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
        CVar uv2 = CVar.FindCVar("wolf_dbg_check");
        if (uv2 != null && uv2.GetInt() != 0)
            Console.Printf("WOLFDBG use: tgt=(%d,%d) dir=%d elev=%d "
                           "exiting=%d", cx, cy, dir,
                           wl != null && wl.ElevatorAt(cx, cy), exiting);
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
