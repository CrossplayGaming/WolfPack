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
    WolfDoor doorAt[4096];
    WolfPushwall pwAt[4096];
    Actor enemyAt[4096];        // moving-actor claims (DoActor marks)

    int areaconnect[1369];      // 37x37 (NUMAREAS)
    bool abpG[37];
    bool madenoise;             // reset each tick (WL_PLAY.C:1404)
    int playerArea;

    int rngIndex;

    static WolfLevel Get()
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
        rngIndex = Random(0, 255);      // US_InitRndT(true)
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
                    }
                    else if (c != 45)                       // '-'
                    {
                        areaG[idx] = c - 65;                // 'A'+area
                    }
                }
                y++;
            }
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

        // InitAreas: flood from the player's area
        if (players[0].mo != null)
        {
            int tx = int(players[0].mo.pos.x) / 64;
            int ty = 63 - (int(players[0].mo.pos.y) / 64);
            playerArea = AreaAt(tx, ty);
        }
        ConnectAreas();
    }

    override void WorldTick()
    {
        madenoise = false;      // reset every frame (WL_PLAY.C:1404)
        // track the player's area (Thrust updates areanumber every move)
        if (players[0].mo != null)
        {
            int tx = int(players[0].mo.pos.x) / 64;
            int ty = 63 - (int(players[0].mo.pos.y) / 64);
            int a = AreaAt(tx, ty);
            if (a >= 0 && a != playerArea)
            {
                playerArea = a;
                ConnectAreas();
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
        if (playerArea < 0 || playerArea > 36)
            return;
        abpG[playerArea] = true;
        Array<int> stack;
        stack.Push(playerArea);
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
