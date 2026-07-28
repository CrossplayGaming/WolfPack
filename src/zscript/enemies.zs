// WolfEnemySim â€” interpreter for the generated state tables, running the
// WL_STATE/WL_ACT2/WL_PLAY actor sim at Wolf-tic fidelity.
//
// Cadence (charter TIC-002 decision): DoActor runs once per engine tic
// with tics=2 â€” the canonical 35 fps DOS cadence. All sim distances are
// integer Wolf GLOBAL units (0x10000/tile); map units = global/1024.
//
// Engine integration: actors are +SOLID +SHOOTABLE so the engine handles
// player collision (Radius 42: 42+22 = the 64-unit MINACTORDIST box) and
// weapon hits (DamageMobj override implements DamageActor â€” sneak double
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
    virtual String DeathSnd() { return ""; }
    virtual void AttackSound() {}
    virtual int ReactionTics(WolfLevel wl) { return 1 + wl.RndT() / 4; }
    virtual void DropItem_() {}
    virtual bool CardinalDiag() { return false; }   // dogs/fake: no doors
    virtual int KillPoints() { return 100; }
    virtual bool BetterShot() { return false; }     // SS/Hans: dist*2/3
    virtual bool DeathCamBoss() { return false; }   // BOSS-003
    virtual class<Actor> ProjectileType() { return null; }

    // A_DeathScream's secret-floor gag (WL_ACT2.C:1063-1080): on the
    // secret floor a 1-in-256 roll replaces any humanoid death cry.
    bool SecretScream()
    {
        WolfLevel wl = WolfLevel.Get();
        if (wl == null || ((Level.levelnum - 1) % 10) != 9)
            return false;
        if (wl.RndT() != 0)
            return false;
        A_StartSound("wolf/death6", CHAN_VOICE);
        return true;
    }

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
    virtual void LazyInit(WolfLevel wl)
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
            if (camHold > 0)
            {
                camHold--;          // held on the standing frame while the
                return;             // death statement plays out in full
            }
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
        if (attackMode)
            PickNearestTarget();        // co-op: hunt the nearest live

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
        case 5: T_Bite(); break;
        case 13: T_DogChase(); break;
        case 6: ChaseMove(false); break; // T_Ghosts: chase, no attack roll
        case 20: BossChase(3); break;   // T_Schabb
        case 21: BossChase(3); break;   // T_Gift
        case 22: BossChase(3); break;   // T_Fat
        case 23: BossChase(1); break;   // T_Fake
        case 24: ThrowProjectile("WolfNeedle", 0x2000); break;
        case 25: ThrowProjectile("WolfRocket", 0x2000); break;
        case 26: ThrowProjectile("WolfFire", 0x1200); break;
        case 14: HitlerMorph(); break;  // A_HitlerMorph
        case 29: A_StartSound("wolf/mechstep", CHAN_BODY); break;
        case 30: A_StartSound("wolf/slurpie", CHAN_VOICE); break;
        case 10:
            if (screamDone)
                screamDone = false;      // replay: already played in full
            else
                DeathSound();
            break;
        case 11: StartDeathCam(); break;    // A_StartDeathCam
        default: break;
        }
    }

    // ------------------------------------------------------------------
    // co-op targeting (netgame audit phase 2). The original has exactly
    // one player; each enemy here holds a target and retargets to the
    // NEAREST live player while awake. Deterministic (positions only),
    // so lockstep-safe; with one player it degenerates to the original.
    // ------------------------------------------------------------------
    int targetPlayer;

    PlayerPawn TargetPM()
    {
        if (playeringame[targetPlayer] && players[targetPlayer].mo != null
            && players[targetPlayer].health > 0)
            return players[targetPlayer].mo;
        for (int i = 0; i < MAXPLAYERS; i++)
            if (playeringame[i] && players[i].mo != null
                && players[i].health > 0)
            {
                targetPlayer = i;
                return players[i].mo;
            }
        return players[targetPlayer].mo;    // last resort: a corpse
    }

    void PickNearestTarget()
    {
        int best = -1, bestD = int.max;
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!playeringame[i] || players[i].mo == null
                || players[i].health <= 0)
                continue;
            int px = int(players[i].mo.pos.x * 1024);
            int py = int((4096.0 - players[i].mo.pos.y) * 1024);
            int d = max(abs(px - wolfX), abs(py - wolfY));
            if (d < bestD)
            {
                bestD = d;
                best = i;
            }
        }
        if (best >= 0)
            targetPlayer = best;
    }

    // ------------------------------------------------------------------
    // sight & activation (WL_STATE.C:1404-1478)
    // ------------------------------------------------------------------
    bool VisibleToPlayer()
    {
        // FL_VISABLE approximation (decision DEC-002): LOS + player FOV
        PlayerPawn pm = TargetPM();
        if (pm == null || !pm.CheckSight(self))
            return false;
        double d = absangle(pm.AngleTo(self), pm.Angle);
        return d <= 33.0;
    }

    // CheckSight (WL_STATE.C:1187-1240) — NOT plain LOS: area gate, a
    // 1.5-tile proximity auto-see, a cardinal FACING test (an enemy does
    // not see the player behind it), then the line trace. The attack code
    // uses CheckLine instead, which ignores facing.
    const MINSIGHT = 0x18000;

    bool CheckSight_()
    {
        WolfLevel wl = WolfLevel.Get();
        if (wl == null || !wl.AreaByPlayer(areanumber))
            return false;
        if (TargetPM() == null)
            return false;
        int dx = PlayerWolfX() - wolfX;
        int dy = PlayerWolfY() - wolfY;
        if (dx > -MINSIGHT && dx < MINSIGHT
            && dy > -MINSIGHT && dy < MINSIGHT)
            return true;                    // real close: automatic
        switch (dir)                        // cardinals only, as in source
        {
        case 2: if (dy > 0) return false; break;    // north
        case 0: if (dx < 0) return false; break;    // east
        case 6: if (dy < 0) return false; break;    // south
        case 4: if (dx > 0) return false; break;    // west
        }
        return CheckLine_();
    }

    bool CheckLine_()
    {
        // CheckLine approximation (DEC-001): engine LOS incl. door slabs
        PlayerPawn pm = TargetPM();
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
                if (!SightAnyPlayer())
                    return false;
                ambushFlag = false;
            }
            else if (!wl.madenoise && !SightAnyPlayer())
                return false;
            temp2 = ReactionTics(wl);
            return false;
        }
        FirstSighting();
        return true;
    }

    // Wolf is single-player: its CheckSight tests THE player, and our
    // targetPlayer defaults to 0 - so dormant enemies were blind to
    // everyone but the host (user repro: E2 mutants ignored the joiner
    // until damaged; damage wakes without sight). The original's rules
    // run unchanged per candidate player; the nearest passing one
    // becomes the target. Deterministic: replicated state, fixed order.
    bool SightAnyPlayer()
    {
        int saved = targetPlayer;
        int best = -1;
        int bestD = int.max;
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!playeringame[i] || players[i].mo == null
                || players[i].health <= 0)
                continue;
            targetPlayer = i;
            if (!CheckSight_())
                continue;
            int px = int(players[i].mo.pos.x * 1024);
            int py = int((4096.0 - players[i].mo.pos.y) * 1024);
            int d = max(abs(px - wolfX), abs(py - wolfY));
            if (d < bestD)
            {
                bestD = d;
                best = i;
            }
        }
        targetPlayer = best >= 0 ? best : saved;
        return best >= 0;
    }

    // MoveObj's too-close-to-player branch (WL_STATE.C:713): ghosts and
    // spectres deal their touch damage here; everyone else just backs up
    virtual void OnPlayerContact() {}

    virtual void FirstSighting()
    {
        SightSound();
        SetState_(ChaseState());
        wolfSpeed *= ChaseSpeedMul();
        if (distance < 0)
            distance = 0;           // ignore the door opening command
        waitDoor = null;
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
        else if (CardinalDiag())
        {
            // dogs use CHECKDIAG even on cardinals: doors block (CHASE-003)
            int s;
            WolfDoor dd;
            [s, dd] = wl.TileState(tileX + dx, tileY + dy);
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

        if (wl.AreaByPlayer(areanumber) && TargetPM() != null)
        {
            int px = PlayerWolfX();
            int py = PlayerWolfY();
            if (abs(wolfX - px) <= MINACTORDIST
                && abs(wolfY - py) <= MINACTORDIST)
            {
                OnPlayerContact();          // ghosts/spectres drain here
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
            PlayerPawn pm = TargetPM();
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
        ChaseMove(dodge);
    }

    void ChaseMove(bool dodge)
    {
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
                break;
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
        PlayerPawn pm = TargetPM();
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
        PlayerPawn pm = TargetPM();
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
        PlayerPawn pm = TargetPM();
        int ptx = int(pm.pos.x) / 64;
        int pty = 63 - (int(pm.pos.y) / 64);
        int dist = Max(abs(tileX - ptx), abs(tileY - pty));
        if (BetterShot())
            dist = dist * 2 / 3;            // ECOMBAT-002
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

    int PlayerWolfX()
    {
        return int(TargetPM().pos.x * 1024);
    }
    int PlayerWolfY()
    {
        return int((4096.0 - TargetPM().pos.y) * 1024);
    }

    // T_DogChase (WL_ACT2.C:3257-3320): dodge-pathing with a bite-range
    // lookahead check each segment; no attack rolls, no door waits
    void T_DogChase()
    {
        if (dir == NODIR)
        {
            SelectDodgeDir();
            if (dir == NODIR)
                return;
        }
        int move = wolfSpeed * 2;
        int loopGuard = 0;
        while (move > 0)
        {
            if (++loopGuard > 200)
                break;
            int dx = abs(PlayerWolfX() - wolfX) - move;
            if (dx <= MINACTORDIST)
            {
                int dy = abs(PlayerWolfY() - wolfY) - move;
                if (dy <= MINACTORDIST)
                {
                    SetState_(ShootState());    // s_dogjump1
                    return;
                }
            }
            if (move < distance)
            {
                MoveObj(move);
                break;
            }
            wolfX = (tileX << 16) + 0x8000;
            wolfY = (tileY << 16) + 0x8000;
            move -= distance;
            SelectDodgeDir();
            if (dir == NODIR)
                return;
        }
    }

    // A_StartDeathCam (WL_ACT2.C:3765-3868). First call starts the
    // replay; the replay ends on this same frame, so the SECOND call is
    // what ends the level victorious.
    virtual int DeathCamState() { return -1; }

    void StartDeathCam()
    {
        WolfDeathCam cam = WolfDeathCam.Get();
        PlayerPawn pm = TargetPM();
        if (cam != null && pm != null
            && cam.Begin(self, killPos))
            return;                     // replay started
        // second call (or no cam): the boss floor is over
        // TODO: episode-end sequence (BJ victory run + text screens)
        Level.ExitLevel(0, false);
    }

    int camHold;
    bool screamDone;

    void StartDeathCamReplay()
    {
        int st = DeathCamState();
        if (st >= 0)
        {
            dead = true;
            // the death statement plays IN FULL over the standing frame
            // before the collapse replays (user-verified original order);
            // the die chain's own scream is suppressed to avoid a double
            DeathSound();
            screamDone = true;
            String snd = DeathSnd();
            camHold = snd == "" ? 60
                    : int(S_GetLength(snd) * 35) + 10;
            SetState_(st);
        }
    }

    // T_Schabb / T_Gift / T_Fat / T_Fake (WL_ACT2.C:2380+): T_Chase with
    // a flat attack roll — US_RndT() < (tics<<shift) — instead of the
    // distance formula. tics = 2 (TIC-002).
    void BossChase(int shift)
    {
        WolfLevel wl = WolfLevel.Get();
        bool dodge = false;
        if (CheckLine_())
        {
            if (wl.RndT() < (2 << shift))
            {
                SetState_(ShootState());
                return;
            }
            dodge = true;
        }
        ChaseMove(dodge);
    }

    // spawn a projectile aimed at the player (T_SchabbThrow / T_GiftThrow
    // / T_FakeFire: atan2 to the player, speed per PROJ-001..003)
    void ThrowProjectile(class<Actor> cls, int speed)
    {
        Actor p = Spawn(cls, pos);
        WolfProjectile wp = WolfProjectile(p);
        if (wp != null)
            wp.InitProjectile(self, speed);
        AttackSound();
    }

    // A_HitlerMorph (WL_ACT2.C:2886-2903): the mech suit dies and the
    // real Hitler steps out with his own HP table, inheriting position.
    void HitlerMorph()
    {
        Actor h = Spawn("WolfHitler", pos);
        WolfEnemySim e = WolfEnemySim(h);
        if (e == null)
            return;
        e.wolfX = wolfX;
        e.wolfY = wolfY;
        e.tileX = tileX;
        e.tileY = tileY;
        e.dir = dir;
        e.distance = distance;
        e.areanumber = areanumber;
        e.attackMode = true;
        e.activeFlag = true;
        e.ambushFlag = false;
        e.simInit = true;
        e.SetState_(e.ChaseState());
    }

    // T_Bite (WL_ACT2.C:3530-3560)
    void T_Bite()
    {
        WolfLevel wl = WolfLevel.Get();
        AttackSound();
        int dx = abs(PlayerWolfX() - wolfX) - TILEGLOBAL;
        if (dx <= MINACTORDIST)
        {
            int dy = abs(PlayerWolfY() - wolfY) - TILEGLOBAL;
            if (dy <= MINACTORDIST && wl.RndT() < 180)
            {
                int dmg = wl.RndT() >> 4;
                if (dmg > 0)
                    TargetPM().DamageMobj(self, self, dmg, 'Melee',
                                             DMG_THRUSTLESS);
            }
        }
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
            KillActor_(source);
        }
        else
        {
            if (!attackMode)
                FirstSighting();
            SetState_(PainState((hitpoints & 1) != 0));
        }
        return 0;                   // engine health untouched
    }

    Vector3 killPos;

    void KillActor_(Actor killer = null)
    {
        // BOSS-003 killx/killy: the KILLER's position (in the original
        // there is only one candidate)
        if (killer != null)
            killPos = killer.pos;
        else if (players[0].mo != null)
            killPos = players[0].mo.pos;
        WolfLevel wl = WolfLevel.Get();
        wl.ReleaseTile(tileX, tileY, self);
        dead = true;
        bShootable = false;
        bSolid = false;
        DropItem_();
        WolfGameState gs = WolfGameState.Get();
        if (gs != null)
            gs.GivePoints(WolfGameState.PnumOf(killer), KillPoints());
        wl.killCount++;
        SetState_(DieState());
        SyncPos();
    }

    void PlaceDrop(class<Actor> cls)
    {
        // PlaceItemType (WL_STATE.C:783-803): the death tile FIRST, and
        // only if that is occupied does it scan the 3x3 — x outer, y
        // inner. Blocking statics count as occupied (they set actorat=1),
        // otherwise a drop can land inside a lamp and be unreachable.
        int tx = wolfX >> 16, ty = wolfY >> 16;
        if (TileFree(tx, ty))
        {
            SpawnDrop(cls, tx, ty);
            return;
        }
        for (int x = tx - 1; x <= tx + 1; x++)
            for (int y = ty - 1; y <= ty + 1; y++)
                if (TileFree(x, y))
                {
                    SpawnDrop(cls, x, y);
                    return;
                }
    }

    bool TileFree(int tx, int ty)
    {
        WolfLevel wl = WolfLevel.Get();
        if (wl == null)
            return false;
        int st;
        WolfDoor dd;
        [st, dd] = wl.TileState(tx, ty);
        if (st != 0)
            return false;
        // solid decorations (barrels, lamps, tables...) block the tile
        BlockThingsIterator it = BlockThingsIterator.CreateFromPos(
            tx * 64 + 32, 4096.0 - (ty * 64 + 32), 0, 0, 24, false);
        while (it.Next())
        {
            Actor a = it.thing;
            if (a != null && a.bSolid && !a.bIsMonster && a != self)
                return false;
        }
        return true;
    }

    void SpawnDrop(class<Actor> cls, int tx, int ty)
    {
        Spawn(cls, (tx * 64 + 32, 4096.0 - (ty * 64 + 32), 0));
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
        if (SecretScream())
            return;
        // sounds[US_RndT()%8] (WL_ACT2.C:1088-1105)
        WolfLevel wl = WolfLevel.Get();
        static const String CRIES[] = { "wolf/death1", "wolf/death2",
            "wolf/death3", "wolf/death4", "wolf/death5", "wolf/death7",
            "wolf/death8", "wolf/death9" };
        A_StartSound(CRIES[wl.RndT() % 8], CHAN_VOICE);
    }
    override void AttackSound() { A_StartSound("wolf/nazifire", CHAN_WEAPON); }
    override void DropItem_() { PlaceDrop("WolfStatic48"); }   // bo_clip2
    override int ReactionTics(WolfLevel wl) { return 1 + wl.RndT() / 4; }
    override int KillPoints() { return 100; }        // KILL-001
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

// ----------------------------------------------------------------------
// Dog — 1 HP, x2 chase speed, CHECKDIAG pathing (cannot open doors),
// bite via the jump sequence. No drops; 200 points (KILL-004).
// ----------------------------------------------------------------------
class WolfDog : WolfEnemySim abstract
{
    override int StateRot(int i) { return WolfDogTable.ROT[i]; }
    override String StateSpr(int i) { return WolfDogTable.SPR[i]; }
    override int StateFrm(int i) { return WolfDogTable.FRM[i]; }
    override int StateTics(int i) { return WolfDogTable.TICS[i]; }
    override int StateThink(int i) { return WolfDogTable.THINK[i]; }
    override int StateAction(int i) { return WolfDogTable.ACT[i]; }
    override int StateNext(int i) { return WolfDogTable.NEXT[i]; }
    override int StandState() { return WolfDogTable.DOGPATH1; }
    override int PathState() { return WolfDogTable.DOGPATH1; }
    override int ChaseState() { return WolfDogTable.DOGCHASE1; }
    override int PainState(bool alt) { return WolfDogTable.DOGCHASE1; } // 1 HP: unreachable
    override int ShootState() { return WolfDogTable.DOGJUMP1; }
    override int DieState() { return WolfDogTable.DOGDIE1; }
    override int ChaseSpeedMul() { return 2; }       // SPEED-005
    override int BaseHP(int skill) { return 1; }
    override bool CardinalDiag() { return true; }    // CHASE-003
    override int KillPoints() { return 200; }
    override void SightSound() { A_StartSound("wolf/dogbark", CHAN_VOICE); }
    override void DeathSound()
    {
        if (!SecretScream())
            A_StartSound("wolf/dogdeath", CHAN_VOICE);
    }
    override void AttackSound() { A_StartSound("wolf/dogattack", CHAN_WEAPON); }
    override int ReactionTics(WolfLevel wl) { return 1 + wl.RndT() / 8; } // REACT-005
}

class WolfDogStand : WolfDog
{
    // dog 'stand' spawn codes are dead code in the original (SpawnStand
    // has no en_dog case; zero uses across all 81 shipped maps) — treat
    // as patrol.
    override void PostBeginPlay()
    {
        wolfSpeed = 1500;           // SPDDOG
        Super.PostBeginPlay();
        InitPatrol();
    }
}

class WolfDogPatrol : WolfDog
{
    override void PostBeginPlay()
    {
        wolfSpeed = 1500;
        Super.PostBeginPlay();
        InitPatrol();
    }
}
