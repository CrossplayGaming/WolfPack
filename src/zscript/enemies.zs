// WolfEnemySim — interpreter for the generated state tables, running the
// WL_STATE/WL_ACT2/WL_PLAY actor sim at Wolf-tic fidelity.
//
// Cadence (charter TIC-002 decision): DoActor runs once per engine tic
// with tics=2 — the canonical 35 fps DOS cadence. All sim distances are
// integer Wolf GLOBAL units (0x10000/tile); map units = global/1024.
//
// Engine integration: actors are +SOLID +SHOOTABLE so the engine handles
// player collision (Radius 42: 42+22 = the 64-unit MINACTORDIST box) and
// weapon hits (DamageMobj override implements DamageActor — sneak double
// damage, parity pain, KillActor). Movement bypasses engine physics
// entirely: the tile sim owns position.
class WolfEnemySim : Actor abstract
{
    // dirtype order (WL_DEF.H): E,NE,N,NW,W,SW,S,SE; nodir = -1
    const NODIR = -1;
    const TILEGLOBAL = 0x10000;
    const MINACTORDIST = 0x10000;
    const RUNSPEED = 6000;

    int wolfX, wolfY;       // global units, y south
    int tileX, tileY;       // DESTINATION tile while moving (source invariant)
    int dir;
    int distance;           // global units to dest center, or -doorindex-1
    int wolfSpeed;          // global units per Wolf tic
    int hitpoints;
    int temp2;              // reaction countdown
    int areanumber;
    int stateIdx;
    int ticcount;
    bool attackMode;        // FL_ATTACKMODE
    bool firstAttack;       // FL_FIRSTATTACK
    bool ambushFlag;        // FL_AMBUSH
    bool activeFlag;
    bool dead;

    Default
    {
        +SOLID +SHOOTABLE +NOGRAVITY
        Radius 42;
        Height 64;
        Health 10000;       // engine health unused; sim owns hitpoints
    }

    // ---- per-enemy hooks (guard defaults; other enemies override) ----
    virtual int TableConst(int which) { return 0; }  // state indices
    virtual int StateRot(int i) { return 0; }
    virtual String StateSpr(int i) { return "GRDS"; }
    virtual int StateFrm(int i) { return 0; }
    virtual int StateTics(int i) { return 0; }
    virtual int StateThink(int i) { return 0; }
    virtual int StateAction(int i) { return 0; }
    virtual int StateNext(int i) { return -1; }
    virtual int StandState() { return 0; }
    virtual int PathState() { return 1; }
    virtual int ChaseState() { return 12; }
    virtual int PainState(bool alt) { return alt ? 8 : 7; }
    virtual int ShootState() { return 9; }
    virtual int DieState() { return 18; }
    virtual int ChaseSpeedMul() { return 3; }        // SPEED-001
    virtual void SightSound() {}
    virtual void DeathSound() {}
    virtual void AttackSound() {}
    virtual int ReactionTics(WolfLevel wl) { return 1 + wl.RndT() / 4; }
    virtual void DropItem_() {}

    // ------------------------------------------------------------------
    int spawnTX, spawnTY;
    bool simInit;

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        tileX = int(pos.x) / 64;
        tileY = 63 - (int(pos.y) / 64);
        spawnTX = tileX;
        spawnTY = tileY;
        wolfX = (tileX << 16) + 0x8000;
        wolfY = (tileY << 16) + 0x8000;
        dir = int(Angle / 45) & 7;
        int skill = G_SkillPropertyInt(SKILLP_ACSReturn);
        hitpoints = BaseHP(skill);
        distance = 0;
        SetState_(StandState());
    }

    // grid-dependent init deferred until WolfLevel has loaded (WorldLoaded
    // runs after PostBeginPlay)
    void LazyInit(WolfLevel wl)
    {
        simInit = true;
        areanumber = wl.AreaAt(spawnTX, spawnTY);
        ambushFlag = wl.AmbushAt(spawnTX, spawnTY);   // FL_AMBUSH
    }

    virtual int BaseHP(int skill) { return 25; }     // guard (HP table)

    void InitPatrol()
    {
        // SpawnPatrol: destination = next tile in dir, claim it
        SetState_(PathState());
        distance = TILEGLOBAL;
        int dx, dy;
        [dx, dy] = DirDelta8(dir);
        tileX += dx;
        tileY += dy;
    }

    static int, int DirDelta8(int d)
    {
        switch (d)
        {
        case 0: return 1, 0;
        case 1: return 1, -1;
        case 2: return 0, -1;
        case 3: return -1, -1;
        case 4: return -1, 0;
        case 5: return -1, 1;
        case 6: return 0, 1;
        default: return 1, 1;   // southeast
        }
    }
    static int Opposite8(int d) { return d == NODIR ? NODIR : (d + 4) & 7; }
    static int DiagOf(int d1, int d2)
    {
        // diagonal[][] table: combine cardinal dirs (E,N,W,S are 0,2,4,6)
        if (d1 == 0 && d2 == 2) return 1;
        if (d1 == 2 && d2 == 0) return 1;
        if (d1 == 2 && d2 == 4) return 3;
        if (d1 == 4 && d2 == 2) return 3;
        if (d1 == 4 && d2 == 6) return 5;
        if (d1 == 6 && d2 == 4) return 5;
        if (d1 == 6 && d2 == 0) return 7;
        if (d1 == 0 && d2 == 6) return 7;
        return NODIR;
    }

    void SetState_(int idx)
    {
        stateIdx = idx;
        ticcount = StateTics(idx);
        UpdateSprite();
    }

    void UpdateSprite()
    {
        sprite = GetSpriteIndex(StateSpr(stateIdx));
        frame = StateFrm(stateIdx);
        Angle = dir == NODIR ? 0 : dir * 45.0;
    }

    void SyncPos()
    {
        SetOrigin((wolfX / 1024.0, 4096.0 - wolfY / 1024.0, 0), true);
    }

    // ------------------------------------------------------------------
    // DoActor (WL_PLAY.C:1260-1345), tics = 2
    // ------------------------------------------------------------------
    override void Tick()
    {
        if (IsFrozen())
            return;
        if (dead)
        {
            // corpse still animates its die states
            RunStateClock(2);
            return;
        }
        WolfLevel wl = WolfLevel.Get();
        if (wl == null)
            return;
        if (!simInit)
            LazyInit(wl);
        if (!activeFlag && !wl.AreaByPlayer(areanumber))
            return;

        wl.ReleaseTile(tileX, tileY, self);

        int t = StateTics(stateIdx);
        if (t == 0)
        {
            DoThink(StateThink(stateIdx));
            if (dead) return;
            wl.ClaimTile(tileX, tileY, self);
            return;
        }
        ticcount -= 2;
        int pumpGuard = 0;
        while (ticcount <= 0)
        {
            if (++pumpGuard > 100)
            {
                Console.Printf("WOLFDBG pump loop: st=%d tc=%d", stateIdx, ticcount);
                break;
            }
            DoThink(StateAction(stateIdx));
            if (dead) return;
            int nxt = StateNext(stateIdx);
            if (nxt < 0)
            {
                Destroy();
                return;
            }
            stateIdx = nxt;
            UpdateSprite();
            int nt = StateTics(stateIdx);
            if (nt == 0)
            {
                ticcount = 0;
                break;
            }
            ticcount += nt;
        }
        DoThink(StateThink(stateIdx));
        if (dead) return;
        wl.ClaimTile(tileX, tileY, self);
        SyncPos();
    }

    void RunStateClock(int tics)
    {
        int t = StateTics(stateIdx);
        if (t == 0)
            return;
        ticcount -= tics;
        while (ticcount <= 0)
        {
            DoThink(StateAction(stateIdx));     // e.g. A_DeathScream on die1
            int nxt = StateNext(stateIdx);
            if (nxt < 0 || nxt == stateIdx)
            {
                ticcount = 0;
                return;
            }
            stateIdx = nxt;
            UpdateSprite();
            int nt = StateTics(stateIdx);
            if (nt == 0)
                return;
            ticcount += nt;
        }
    }

    void DoThink(int id)
    {
        switch (id)
        {
        case 1: T_Stand(); break;
        case 2: T_Path(); break;
        case 3: T_Chase(); break;
        case 4: T_Shoot(); break;
        case 10: DeathSound(); break;
        default: break;
        }
    }

    // ------------------------------------------------------------------
    // sight & activation (WL_STATE.C:1404-1478)
    // ------------------------------------------------------------------
    bool VisibleToPlayer()
    {
        // FL_VISABLE approximation (decision DEC-002): LOS + player FOV
        PlayerPawn pm = players[0].mo;
        if (pm == null || !pm.CheckSight(self))
            return false;
        double d = absangle(pm.AngleTo(self), pm.Angle);
        return d <= 33.0;
    }

    bool CheckLine_()
    {
        // CheckLine approximation (DEC-001): engine LOS incl. door slabs
        PlayerPawn pm = players[0].mo;
        return pm != null && CheckSight(pm);
    }

    bool SightPlayer()
    {
        WolfLevel wl = WolfLevel.Get();
        if (temp2 != 0)
        {
            temp2 -= 2;
            if (temp2 > 0)
                return false;
            temp2 = 0;
        }
        else
        {
            if (!wl.AreaByPlayer(areanumber))
                return false;
            if (ambushFlag)
            {
                if (!CheckLine_())
                    return false;
                ambushFlag = false;
            }
            else if (!wl.madenoise && !CheckLine_())
                return false;
            temp2 = ReactionTics(wl);
            return false;
        }
        FirstSighting();
        return true;
    }

    virtual void FirstSighting()
    {
        SightSound();
        SetState_(ChaseState());
        wolfSpeed *= ChaseSpeedMul();
        attackMode = true;
        firstAttack = true;
        activeFlag = true;
    }

    // ------------------------------------------------------------------
    // tile walking (WL_STATE.C:181-333)
    // ------------------------------------------------------------------
    // returns: 0 blocked, 1 ok, 2 waiting on door (distance encoded)
    int TryWalk_()
    {
        WolfLevel wl = WolfLevel.Get();
        int dx, dy;
        [dx, dy] = DirDelta8(dir);
        bool diagonal = (dir & 1) == 1;
        int doorIdx = -1;
        WolfDoor doorRef = null;

        if (diagonal)
        {
            // CHECKDIAG on the three involved tiles: doors always block
            int s;
            WolfDoor dd;
            [s, dd] = wl.TileState(tileX + dx, tileY + dy);
            if (s != 0) return 0;
            [s, dd] = wl.TileState(tileX + dx, tileY);
            if (s != 0) return 0;
            [s, dd] = wl.TileState(tileX, tileY + dy);
            if (s != 0) return 0;
        }
        else
        {
            // CHECKSIDE: doors passable (recorded), walls/actors block
            int s;
            WolfDoor dd;
            [s, dd] = wl.TileState(tileX + dx, tileY + dy);
            if (s == 1) return 0;
            if (s == 2) doorRef = dd;
        }

        tileX += dx;
        tileY += dy;

        if (doorRef != null)
        {
            doorRef.StartOpen();
            waitDoor = doorRef;
            distance = -2;      // sentinel: waiting on door
            return 2;
        }
        areanumber = wl.AreaAt(tileX, tileY);
        distance = TILEGLOBAL;
        return 1;
    }
    WolfDoor waitDoor;

    void SelectPathDir()
    {
        // turn markers (MAP-016) via WolfMarker things on the tile
        int spot = TurnAt(tileX, tileY);
        if (spot >= 0)
            dir = spot;
        distance = TILEGLOBAL;
        if (TryWalk_() == 0)
            dir = NODIR;
    }

    int TurnAt(int tx, int ty)
    {
        ThinkerIterator it = ThinkerIterator.Create("WolfMarker");
        WolfMarker m;
        while ((m = WolfMarker(it.Next())) != null)
        {
            if (m.tileX != tx || m.tileY != ty)
                continue;
            if (m is "WolfTurnE") return 0;
            if (m is "WolfTurnNE") return 1;
            if (m is "WolfTurnN") return 2;
            if (m is "WolfTurnNW") return 3;
            if (m is "WolfTurnW") return 4;
            if (m is "WolfTurnSW") return 5;
            if (m is "WolfTurnS") return 6;
            if (m is "WolfTurnSE") return 7;
        }
        return -1;
    }

    // MoveObj (WL_STATE.C:659-755)
    void MoveObj(int move)
    {
        WolfLevel wl = WolfLevel.Get();
        int dx, dy;
        [dx, dy] = DirDelta8(dir);
        wolfX += dx * move;
        wolfY += dy * move;

        if (wl.AreaByPlayer(areanumber) && players[0].mo != null)
        {
            int px = int(players[0].mo.pos.x * 1024);
            int py = int((4096.0 - players[0].mo.pos.y) * 1024);
            if (abs(wolfX - px) <= MINACTORDIST
                && abs(wolfY - py) <= MINACTORDIST)
            {
                wolfX -= dx * move;         // back up, keep distance
                wolfY -= dy * move;
                return;
            }
        }
        distance -= move;
    }

    // ------------------------------------------------------------------
    // thinks
    // ------------------------------------------------------------------
    void T_Stand()
    {
        SightPlayer();
    }

    void T_Path()
    {
        if (SightPlayer())
            return;
        if (dir == NODIR)
        {
            SelectPathDir();
            if (dir == NODIR)
                return;
        }
        int move = wolfSpeed * 2;
        int loopGuard = 0;
        while (move > 0)
        {
            if (++loopGuard > 200)
            {
                Console.Printf("WOLFDBG T_Path loop: move=%d dist=%d dir=%d tile=%d,%d st=%d",
                               move, distance, dir, tileX, tileY, stateIdx);
                break;
            }
            if (distance < 0)
            {
                // waiting for a door
                if (waitDoor == null || waitDoor.doorAction != WolfDoor.DR_OPEN)
                {
                    if (waitDoor != null) waitDoor.StartOpen();
                    return;
                }
                distance = TILEGLOBAL;
                waitDoor = null;
            }
            if (move < distance)
            {
                MoveObj(move);
                break;
            }
            // reached goal tile center
            wolfX = (tileX << 16) + 0x8000;
            wolfY = (tileY << 16) + 0x8000;
            move -= distance;
            SelectPathDir();
            if (dir == NODIR)
                return;
        }
    }

    void T_Chase()
    {
        WolfLevel wl = WolfLevel.Get();
        bool dodge = false;
        if (CheckLine_())
        {
            PlayerPawn pm = players[0].mo;
            int ptx = int(pm.pos.x) / 64;
            int pty = 63 - (int(pm.pos.y) / 64);
            int dist = Max(abs(tileX - ptx), abs(tileY - pty));
            int chance;
            if (dist == 0 || (dist == 1 && distance < 0x4000))
                chance = 300;
            else
                chance = (2 << 4) / dist;       // (tics<<4)/dist, tics=2
            if (wl.RndT() < chance)
            {
                SetState_(ShootState());
                return;
            }
            dodge = true;
        }
        if (dir == NODIR)
        {
            if (dodge) SelectDodgeDir();
            else SelectChaseDir();
            if (dir == NODIR)
                return;
        }
        int move = wolfSpeed * 2;
        int loopGuard = 0;
        while (move > 0)
        {
            if (++loopGuard > 200)
            {
                Console.Printf("WOLFDBG T_Chase loop: move=%d dist=%d dir=%d tile=%d,%d st=%d",
                               move, distance, dir, tileX, tileY, stateIdx);
                break;
            }
            if (distance < 0)
            {
                if (waitDoor == null || waitDoor.doorAction != WolfDoor.DR_OPEN)
                {
                    if (waitDoor != null) waitDoor.StartOpen();
                    return;
                }
                distance = TILEGLOBAL;
                waitDoor = null;
            }
            if (move < distance)
            {
                MoveObj(move);
                break;
            }
            wolfX = (tileX << 16) + 0x8000;
            wolfY = (tileY << 16) + 0x8000;
            move -= distance;
            if (dodge) SelectDodgeDir();
            else SelectChaseDir();
            if (dir == NODIR)
                return;
        }
    }

    // SelectDodgeDir (WL_STATE.C:359-443)
    void SelectDodgeDir()
    {
        WolfLevel wl = WolfLevel.Get();
        PlayerPawn pm = players[0].mo;
        int turnaround = firstAttack ? NODIR : Opposite8(dir);
        firstAttack = false;

        int deltax = (int(pm.pos.x) / 64) - tileX;
        int deltay = (63 - int(pm.pos.y) / 64) - tileY;

        int dtry[5];
        dtry[1] = deltax > 0 ? 0 : 4;
        dtry[3] = deltax > 0 ? 4 : 0;
        dtry[2] = deltay > 0 ? 6 : 2;
        dtry[4] = deltay > 0 ? 2 : 6;

        if (abs(deltax) > abs(deltay))
        {
            int t = dtry[1]; dtry[1] = dtry[2]; dtry[2] = t;
            t = dtry[3]; dtry[3] = dtry[4]; dtry[4] = t;
        }
        if (wl.RndT() < 128)
        {
            int t = dtry[1]; dtry[1] = dtry[2]; dtry[2] = t;
            t = dtry[3]; dtry[3] = dtry[4]; dtry[4] = t;
        }
        dtry[0] = DiagOf(dtry[1], dtry[2]);

        for (int i = 0; i < 5; i++)
        {
            if (dtry[i] == NODIR || dtry[i] == turnaround)
                continue;
            dir = dtry[i];
            if (TryWalk_() != 0)
                return;
        }
        if (turnaround != NODIR)
        {
            dir = turnaround;
            if (TryWalk_() != 0)
                return;
        }
        dir = NODIR;
    }

    // SelectChaseDir (WL_STATE.C:475-570)
    void SelectChaseDir()
    {
        WolfLevel wl = WolfLevel.Get();
        PlayerPawn pm = players[0].mo;
        int olddir = dir;
        int turnaround = Opposite8(olddir);

        int deltax = (int(pm.pos.x) / 64) - tileX;
        int deltay = (63 - int(pm.pos.y) / 64) - tileY;

        int d1 = NODIR, d2 = NODIR;
        if (deltax > 0) d1 = 0;
        else if (deltax < 0) d1 = 4;
        if (deltay > 0) d2 = 6;
        else if (deltay < 0) d2 = 2;

        if (abs(deltay) > abs(deltax))
        {
            int t = d1; d1 = d2; d2 = t;
        }
        if (d1 == turnaround) d1 = NODIR;
        if (d2 == turnaround) d2 = NODIR;

        if (d1 != NODIR) { dir = d1; if (TryWalk_() != 0) return; }
        if (d2 != NODIR) { dir = d2; if (TryWalk_() != 0) return; }
        if (olddir != NODIR) { dir = olddir; if (TryWalk_() != 0) return; }

        if (wl.RndT() > 128)
        {
            // source sweeps dirtype north..west ascending; in our dir
            // encoding the cardinals ascend E(0),N(2),W(4),S(6)
            for (int td = 0; td <= 6; td += 2)
            {
                if (td != turnaround)
                {
                    dir = td;
                    if (TryWalk_() != 0) return;
                }
            }
        }
        else
        {
            for (int td = 6; td >= 0; td -= 2)
            {
                if (td != turnaround)
                {
                    dir = td;
                    if (TryWalk_() != 0) return;
                }
            }
        }
        if (turnaround != NODIR)
        {
            dir = turnaround;
            if (TryWalk_() != 0) return;
        }
        dir = NODIR;
    }

    // T_Shoot (WL_ACT2.C:3444-3518)
    void T_Shoot()
    {
        WolfLevel wl = WolfLevel.Get();
        if (!wl.AreaByPlayer(areanumber))
            return;
        if (!CheckLine_())
            return;
        PlayerPawn pm = players[0].mo;
        int ptx = int(pm.pos.x) / 64;
        int pty = 63 - (int(pm.pos.y) / 64);
        int dist = Max(abs(tileX - ptx), abs(tileY - pty));
        // SS/Hans dist*2/3 handled by subclass override later
        bool running = WolfPlayer(pm) != null && WolfPlayer(pm).bIsRunning;
        bool visible = VisibleToPlayer();
        int hitchance;
        if (running)
            hitchance = visible ? 160 - dist * 16 : 160 - dist * 8;
        else
            hitchance = visible ? 256 - dist * 16 : 256 - dist * 8;
        if (wl.RndT() < hitchance)
        {
            int damage;
            if (dist < 2)      damage = wl.RndT() >> 2;
            else if (dist < 4) damage = wl.RndT() >> 3;
            else               damage = wl.RndT() >> 4;
            if (damage > 0)
                pm.DamageMobj(self, self, damage, 'Bullet', DMG_THRUSTLESS);
        }
        AttackSound();
    }

    // ------------------------------------------------------------------
    // DamageActor / KillActor (WL_STATE.C:810-1010)
    // ------------------------------------------------------------------
    override int DamageMobj(Actor inflictor, Actor source, int damage,
                            Name mod, int flags, double angle)
    {
        if (dead)
            return 0;
        WolfLevel wl = WolfLevel.Get();
        wl.madenoise = true;
        if (!attackMode)
            damage <<= 1;           // sneak attack (ECOMBAT-008)
        hitpoints -= damage;
        if (hitpoints <= 0)
        {
            KillActor_();
        }
        else
        {
            if (!attackMode)
                FirstSighting();
            SetState_(PainState((hitpoints & 1) != 0));
        }
        return 0;                   // engine health untouched
    }

    void KillActor_()
    {
        WolfLevel wl = WolfLevel.Get();
        wl.ReleaseTile(tileX, tileY, self);
        dead = true;
        bShootable = false;
        bSolid = false;
        DropItem_();
        // TODO Phase 2 stats: GivePoints, killcount
        SetState_(DieState());
        SyncPos();
    }

    void PlaceDrop(class<Actor> cls)
    {
        // PlaceItemType: at tile, or first free neighbor (WL_STATE.C:783-803)
        WolfLevel wl = WolfLevel.Get();
        int tx = wolfX >> 16, ty = wolfY >> 16;
        for (int dy = -1; dy <= 1; dy++)
            for (int dx = -1; dx <= 1; dx++)
            {
                int s;
                WolfDoor dd;
                [s, dd] = wl.TileState(tx + dx, ty + dy);
                if ((dx == 0 && dy == 0) || s == 0)
                {
                    Spawn(cls, ((tx + dx) * 64 + 32,
                                4096.0 - ((ty + dy) * 64 + 32), 0));
                    return;
                }
            }
    }
}

// ----------------------------------------------------------------------
// Guard
// ----------------------------------------------------------------------
class WolfGuard : WolfEnemySim abstract
{
    Default
    {
        //$Category Wolf
    }
    // never entered: registers the sprite names with the engine (sprite
    // lumps alone don't create sprite entries; GetSpriteIndex needs these)
    States
    {
    SpriteRegistry:
        GRDS A -1;
        GRDW ABCD -1;
        GRDP AB -1;
        GRDD ABC -1;
        SDED A -1;
        GRDA ABC -1;
        Stop;
    }
    override int StateRot(int i) { return WolfGuardTable.ROT[i]; }
    override String StateSpr(int i) { return WolfGuardTable.SPR[i]; }
    override int StateFrm(int i) { return WolfGuardTable.FRM[i]; }
    override int StateTics(int i) { return WolfGuardTable.TICS[i]; }
    override int StateThink(int i) { return WolfGuardTable.THINK[i]; }
    override int StateAction(int i) { return WolfGuardTable.ACT[i]; }
    override int StateNext(int i) { return WolfGuardTable.NEXT[i]; }
    override int StandState() { return WolfGuardTable.GRDSTAND; }
    override int PathState() { return WolfGuardTable.GRDPATH1; }
    override int ChaseState() { return WolfGuardTable.GRDCHASE1; }
    override int PainState(bool alt)
    {
        return alt ? WolfGuardTable.GRDPAIN : WolfGuardTable.GRDPAIN1;
    }
    override int ShootState() { return WolfGuardTable.GRDSHOOT1; }
    override int DieState() { return WolfGuardTable.GRDDIE1; }
    override int BaseHP(int skill) { return 25; }    // HP table: guard
    override void SightSound() { A_StartSound("wolf/halt", CHAN_VOICE); }
    override void DeathSound()
    {
        WolfLevel wl = WolfLevel.Get();
        A_StartSound(wl.RndT() < 128 ? "wolf/death1" : "wolf/death2",
                     CHAN_VOICE);
    }
    override void AttackSound() { A_StartSound("wolf/nazifire", CHAN_WEAPON); }
    override void DropItem_() { PlaceDrop("WolfStatic48"); }   // bo_clip2
    override int ReactionTics(WolfLevel wl) { return 1 + wl.RndT() / 4; }
}

class WolfGuardStand : WolfGuard
{
    Default
    {
        Speed 0;
    }
    override void PostBeginPlay()
    {
        wolfSpeed = 512;            // SPDPATROL
        Super.PostBeginPlay();
    }
}

class WolfGuardPatrol : WolfGuard
{
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
        InitPatrol();
    }
}
