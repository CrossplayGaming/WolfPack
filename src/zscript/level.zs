// WolfLevel — the sim's world state: tilemap/actorat grids, area
// connectivity, noise flag, and the US_RndT stream.
//
// Grids parse from the converter's wolfdata/MAPxx.txt lump:
//   section 1: 64 rows of '#' wall / 'D' door / 'P' pushwall / '.' open
//   section 2: 64 rows of area codes ('A'+area, '-' none)
//
// Charter: CHASE-001 actorat encoding, DOOR-007/008/009 area joins,
// TILE-001/002 areas, RNG-001 rndtable.
class WolfLevel : EventHandler
{
    // static solid map: 0 open, 1 wall, 2 door tile, 3 pushwall tile
    int solidG[4096];
    int areaG[4096];            // -1 = none
    bool ambushG[4096];         // AMBUSHTILE marks (TILE-003)
    bool elevG[4096];           // ELEVATORTILE switch walls (EXIT-001)
    WolfDoor doorAt[4096];
    WolfPushwall pwAt[4096];
    Actor enemyAt[4096];        // moving-actor claims (DoActor marks)

    int areaconnect[1369];      // 37x37 (NUMAREAS)
    bool abpG[37];
    // madenoise (WL_PLAY.C:1404) - set by the player's gun, read by
    // every SightPlayer, cleared each frame. In the original the player
    // is object zero, so it always fires BEFORE the actors think and
    // they all see the flag within the same frame. Here thinker order
    // is the engine's business, and measurement showed the enemies
    // always run first: over 118 SightPlayer calls spanning a shot, not
    // one saw the flag set, so firing woke nobody who could not already
    // see you. Double-buffering fixes it order-independently - a shot
    // raises noisePending, and WorldTick promotes that into madenoise
    // for one whole tick, which every enemy then observes exactly once.
    bool madenoise, noisePending;
    int noiseTics;              // diagnostic: tics madenoise was set
    int playerAreas[MAXPLAYERS];    // one seed per player (co-op)

    int rngIndex;

    // per-level stats (tally pass): found counts + totals
    int killCount, secretCount, treasureCount;
    int floorNum;
    int killTotal, secretTotal, treasureTotal;

    clearscope static WolfLevel Get()
    {
        return WolfLevel(EventHandler.Find("WolfLevel"));
    }

    // US_RndT: index+1 per call, wraps (ID_US_A.ASM)
    int RndT()
    {
        rngIndex = (rngIndex + 1) & 255;
        return WolfRndTable.T[rngIndex];
    }

    override void WorldLoaded(WorldEvent e)
    {
        // Loading a save left the MENU song playing over the level
        // (user report): the menu starts WONDERIN itself, and only
        // BackOut puts the level song back - a path a save load never
        // takes. Claim the level's music here, where every entry to a
        // level passes, save loads included.
        if (Level.MapName != "TITLEMAP" && Level.Music != "")
            S_ChangeMusic(Level.Music, Level.musicorder, true);
        rngIndex = Random(0, 255);      // US_InitRndT(true)
        floorNum = ((Level.levelnum - 1) % 10) + 1;
        for (int i = 0; i < 4096; i++)
        {
            solidG[i] = 0;
            areaG[i] = -1;
        }

        int lump = Wads.CheckNumForFullName(
            String.Format("wolfdata/%s.txt", level.mapname));
        if (lump >= 0)
        {
            Array<String> rows;
            Wads.ReadLump(lump).Split(rows, "\n");
            int section = 0, y = 0;
            for (int i = 0; i < rows.Size(); i++)
            {
                String r = rows[i];
                if (r.Length() < 64)
                {
                    if (y > 0) { section++; y = 0; }
                    continue;
                }
                for (int x = 0; x < 64; x++)
                {
                    int c = r.ByteAt(x);
                    int idx = y * 64 + x;
                    if (section == 0)
                    {
                        if (c == 35)      solidG[idx] = 1;   // '#'
                        else if (c == 68) solidG[idx] = 2;   // 'D'
                        else if (c == 80) solidG[idx] = 3;   // 'P'
                        else if (c == 97) ambushG[idx] = true; // 'a'
                        else if (c == 69) { solidG[idx] = 1;   // 'E'
                                            elevG[idx] = true; }
                    }
                    else if (c != 45)                       // '-'
                    {
                        areaG[idx] = c - 65;                // 'A'+area
                    }
                }
                y++;
            }
        }

        // EXIT-007: keys reset every floor; weapons and ammo carry
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (players[i].mo == null)
                continue;
            // The pawn TRAVELS between levels with its fields intact,
            // so the one-shot exit latch WolfUse sets must be cleared
            // here or the SECOND elevator of a session refuses
            // silently (user repro: E1M1 secret elevator worked, the
            // secret level's did not; every -warp probe passed because
            // -warp spawns a fresh pawn with the latch clear).
            let wpx = WolfPlayer(players[i].mo);
            if (wpx != null)
                wpx.exiting = false;
            players[i].mo.TakeInventory("WolfGoldKey", 99);
            players[i].mo.TakeInventory("WolfSilverKey", 99);
        }

        // register doors and pushwalls by tile
        ThinkerIterator dit = ThinkerIterator.Create("WolfDoor");
        WolfDoor d;
        while ((d = WolfDoor(dit.Next())) != null)
            doorAt[d.tileY * 64 + d.tileX] = d;
        ThinkerIterator pit = ThinkerIterator.Create("WolfPushwall");
        WolfPushwall p;
        while ((p = WolfPushwall(pit.Next())) != null)
            pwAt[p.tileY * 64 + p.tileX] = p;

        // stat totals (spawn-time counting like the original)
        ThinkerIterator eit = ThinkerIterator.Create("WolfEnemySim");
        while (eit.Next() != null)
            killTotal++;
        ThinkerIterator sit = ThinkerIterator.Create("WolfPushwall");
        while (sit.Next() != null)
            secretTotal++;
        ThinkerIterator tit = ThinkerIterator.Create("WolfPickup");
        WolfPickup pk;
        while ((pk = WolfPickup(tit.Next())) != null)
            if (pk.BonusKind() >= WolfPickup.BO_CROSS
                && pk.BonusKind() <= WolfPickup.BO_FULLHEAL)
                treasureTotal++;

        // InitAreas: flood from every in-game player's area
        for (int pn = 0; pn < MAXPLAYERS; pn++)
        {
            playerAreas[pn] = -1;
            if (playeringame[pn] && players[pn].mo != null)
            {
                int tx = int(players[pn].mo.pos.x) / 64;
                int ty = 63 - (int(players[pn].mo.pos.y) / 64);
                playerAreas[pn] = AreaAt(tx, ty);
            }
        }
        ConnectAreas();
    }

    // Bonus award happens in play scope at level exit; the intermission
    // only animates the count-up (it is UI scope and cannot score).
    override void WorldUnloaded(WorldEvent e)
    {
        WolfGameState gs = WolfGameState.Get();
        if (gs == null || gs.deathRestart)
            return;                 // died: no tally, no bonus
        int levelSec = Level.time / TICRATE;
        int parSec = Level.partime;
        int timeLeft = parSec > levelSec ? parSec - levelSec : 0;
        int bonus = timeLeft * 500;                 // SCORE-002
        if (killTotal > 0 && killCount * 100 / killTotal == 100)
            bonus += 10000;                         // SCORE-003
        if (secretTotal > 0 && secretCount * 100 / secretTotal == 100)
            bonus += 10000;
        if (treasureTotal > 0 && treasureCount * 100 / treasureTotal == 100)
            bonus += 10000;
        if (bonus > 0)
            for (int pn = 0; pn < MAXPLAYERS; pn++)
                if (playeringame[pn])
                    gs.GivePoints(pn, bonus);
    }

    override void WorldTick()
    {
        madenoise = noisePending;   // one full tick, whatever the order
        noisePending = false;
        if (madenoise)
            noiseTics++;            // diagnostic (wolf_dbg_alertcount)
        // track every player's area (Thrust updates it each move)
        for (int pn = 0; pn < MAXPLAYERS; pn++)
        {
            if (!playeringame[pn] || players[pn].mo == null)
                continue;
            int tx = int(players[pn].mo.pos.x) / 64;
            int ty = 63 - (int(players[pn].mo.pos.y) / 64);
            int a = AreaAt(tx, ty);
            if (a >= 0 && a != playerAreas[pn])
            {
                playerAreas[pn] = a;
                ConnectAreas();
            }
        }
    }

    bool ElevatorAt(int tx, int ty)
    {
        return tx >= 0 && tx <= 63 && ty >= 0 && ty <= 63
               && elevG[ty * 64 + tx];
    }

    // EXIT-003: flip the switch to its "used" texture (tilemap[x][y]++ ->
    // the next wall pair). Code 21 -> 22, i.e. WALL040/041 -> WALL042/043.
    void FlipSwitch(int tx, int ty)
    {
        double x1 = tx * 64, x2 = x1 + 64;
        double y1 = (63 - ty) * 64, y2 = y1 + 64;
        for (int i = 0; i < Level.Lines.Size(); i++)
        {
            Line l = Level.Lines[i];
            Vector2 mid = (l.v1.p + l.v2.p) / 2;
            if (mid.x < x1 - 1 || mid.x > x2 + 1
                || mid.y < y1 - 1 || mid.y > y2 + 1)
                continue;
            for (int sn = 0; sn < 2; sn++)
            {
                Side sd = l.sidedef[sn];
                if (sd == null)
                    continue;
                TextureID t = sd.GetTexture(Side.mid);
                String nm = TexMan.GetName(t);
                if (nm == "WALL040" || nm == "WALL041")
                {
                    String rep = nm == "WALL040" ? "WALL042" : "WALL043";
                    sd.SetTexture(Side.mid,
                        TexMan.CheckForTexture(rep, TexMan.Type_Any));
                }
            }
        }
    }

    bool AmbushAt(int tx, int ty)
    {
        return tx >= 0 && tx <= 63 && ty >= 0 && ty <= 63
               && ambushG[ty * 64 + tx];
    }

    int AreaAt(int tx, int ty)
    {
        if (tx < 0 || tx > 63 || ty < 0 || ty > 63)
            return -1;
        return areaG[ty * 64 + tx];
    }

    // --- area connectivity (WL_ACT1.C:293-320) ---
    void DoorConnect(int a1, int a2, int delta)   // DOOR-008/009
    {
        if (a1 < 0 || a2 < 0 || a1 > 36 || a2 > 36)
            return;
        areaconnect[a1 * 37 + a2] += delta;
        areaconnect[a2 * 37 + a1] += delta;
        ConnectAreas();
    }

    void ConnectAreas()
    {
        for (int i = 0; i < 37; i++)
            abpG[i] = false;
        Array<int> stack;
        // co-op: connectivity is the UNION over all players' areas -
        // areabyplayer, plural, exactly as the original named it
        for (int pn = 0; pn < MAXPLAYERS; pn++)
        {
            int pa = playerAreas[pn];
            if (pa >= 0 && pa <= 36 && !abpG[pa])
            {
                abpG[pa] = true;
                stack.Push(pa);
            }
        }
        while (stack.Size() > 0)
        {
            int a = stack[stack.Size() - 1];
            stack.Pop();
            for (int i = 0; i < 37; i++)
            {
                if (areaconnect[a * 37 + i] > 0 && !abpG[i])
                {
                    abpG[i] = true;
                    stack.Push(i);
                }
            }
        }
    }

    bool AreaByPlayer(int a)
    {
        return a >= 0 && a <= 36 && abpG[a];
    }

    // --- actorat queries (CHASE-001 encoding) ---
    // returns: 0 free, 1 solid, 2 door (out doorRef)
    int, WolfDoor TileState(int tx, int ty)
    {
        if (tx < 0 || tx > 63 || ty < 0 || ty > 63)
            return 1, null;
        int idx = ty * 64 + tx;
        int s = solidG[idx];
        if (s == 1)
            return 1, null;
        if (s == 2)
            return 2, doorAt[idx];
        if (s == 3)
        {
            WolfPushwall p = pwAt[idx];
            // pushwall tile: solid while the cube is parked here
            if (p != null && p.state_ == 0)
                return 1, null;
            // cube moved away (or moving): treat per its current tile below
        }
        // dynamic: a parked/done cube may now occupy this tile
        WolfPushwall q = PwActive(tx, ty);
        if (q != null)
            return 1, null;
        if (enemyAt[idx] != null && enemyAt[idx].health > 0)
            return 1, null;
        return 0, null;
    }

    WolfPushwall PwActive(int tx, int ty)
    {
        ThinkerIterator it = ThinkerIterator.Create("WolfPushwall");
        WolfPushwall p;
        while ((p = WolfPushwall(it.Next())) != null)
            if (p.tileX == tx && p.tileY == ty && p.state_ != 1)
                return p;
        return null;
    }

    // actorat[tx][ty] - the sim's claim, which an actor takes on its
    // DESTINATION tile the moment TryWalk grants the move, before it
    // has physically travelled there (DoActor, WL_PLAY.C:1338)
    Actor ActorAt(int tx, int ty)
    {
        if (tx < 0 || tx > 63 || ty < 0 || ty > 63)
            return null;
        return enemyAt[ty * 64 + tx];
    }

    void ClaimTile(int tx, int ty, Actor who)
    {
        if (tx >= 0 && tx <= 63 && ty >= 0 && ty <= 63)
            enemyAt[ty * 64 + tx] = who;
    }

    void ReleaseTile(int tx, int ty, Actor who)
    {
        if (tx >= 0 && tx <= 63 && ty >= 0 && ty <= 63
            && enemyAt[ty * 64 + tx] == who)
            enemyAt[ty * 64 + tx] = null;
    }
}
