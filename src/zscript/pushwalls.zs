// WolfPushwall — PushWall/MovePWalls (WL_ACT1.C:732-897) driving a 64x64
// polyobject cube.
//
// Charter refs:
//   PWALL-001 travel 2 tiles (128 state units/tile, stop when state > 256)
//   PWALL-002 blocked-by-actor at tile boundary -> stop where it is
//   PWALL-003 only one pushwall moving at a time
//   PWALL-006 push refusal if the tile beyond is occupied; push dir =
//             player facing; secretcount++; PUSHWALLSND
//
// Speed: pwallpos = (state/2)&63 -> 0.5 map units per Wolf tic
// = 1 unit per engine tic (Polyobj_Move speed 8). Full travel 128 tics.
// Static travel limits (walls/doors/parked cubes) come from the converter
// in args[1..4] (E,N,W,S); dynamic blockers (actors, moved cubes) are
// checked at the tile boundary like the source.
class WolfPushwall : Actor
{
    int polyId;
    int maxTravel[4];       // tiles, indexed by dir: 0=E 1=N 2=W 3=S
    int tileX, tileY;       // current Wolf tile
    int state_;             // 0 idle, 1 moving, 2 done
    int dirIdx;
    int unitsMoved;
    int plannedTiles;

    Default
    {
        +NOBLOCKMAP +NOSECTOR +NOINTERACTION +NOGRAVITY +DONTSPLASH
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        polyId = args[0];
        maxTravel[0] = args[1];
        maxTravel[1] = args[2];
        maxTravel[2] = args[3];
        maxTravel[3] = args[4];
        tileX = int(pos.x) / 64;
        tileY = 63 - (int(pos.y) / 64);
    }

    // dir deltas in WOLF tile coords (y grows south)
    static int, int DirDelta(int d)
    {
        switch (d)
        {
        case 0: return 1, 0;    // east
        case 1: return 0, -1;   // north
        case 2: return -1, 0;   // west
        default: return 0, 1;   // south
        }
    }
    static int DirAngleByte(int d) { return d * 64; }  // UDMF: E,N,W,S

    static bool AnyMoving()
    {
        ThinkerIterator it = ThinkerIterator.Create("WolfPushwall");
        WolfPushwall p;
        while ((p = WolfPushwall(it.Next())) != null)
            if (p.state_ == 1)
                return true;
        return false;
    }

    bool TileOccupied(int tx, int ty)
    {
        // actors registered by center tile, like actorat (PWALL-002)
        double x1 = tx * 64, x2 = x1 + 64;
        double y1 = (63 - ty) * 64, y2 = y1 + 64;
        ThinkerIterator it = ThinkerIterator.Create("Actor");
        Actor a;
        while ((a = Actor(it.Next())) != null)
        {
            if (!a.bShootable && !a.player)
                continue;
            if (a.pos.x >= x1 && a.pos.x < x2 &&
                a.pos.y >= y1 && a.pos.y < y2)
                return true;
        }
        // parked or finished cubes block too
        ThinkerIterator pit = ThinkerIterator.Create("WolfPushwall");
        WolfPushwall p;
        while ((p = WolfPushwall(pit.Next())) != null)
            if (p != self && p.state_ != 1 && p.tileX == tx && p.tileY == ty)
                return true;
        return false;
    }

    // PushWall (WL_ACT1.C:732-797)
    void Push(int d, Actor user)
    {
        if (state_ != 0)
            return;
        if (AnyMoving())                    // PWALL-003
            return;
        int dx, dy;
        [dx, dy] = DirDelta(d);
        if (maxTravel[d] == 0 || TileOccupied(tileX + dx, tileY + dy))
            return;                         // NOWAYSND lands with audio pass

        WolfLevel wl = WolfLevel.Get();
        if (wl != null)
            wl.secretCount++;           // PWALL-006
        A_StartSound("wolf/pushwall", CHAN_AUTO, attenuation: 1.0);
        dirIdx = d;
        plannedTiles = Min(2, maxTravel[d]);
        unitsMoved = 0;
        state_ = 1;
        Level.ExecuteSpecial(4, self, null, false,      // Polyobj_Move
                             polyId, 8, DirAngleByte(d),
                             plannedTiles * 64);
    }

    override void Tick()
    {
        Super.Tick();
        if (state_ != 1)
            return;
        unitsMoved++;
        if (unitsMoved == 64)
        {
            // crossed the first tile boundary: advance our tile, then per
            // the source, stop dead at the boundary if the next is occupied
            int dx, dy;
            [dx, dy] = DirDelta(dirIdx);
            tileX += dx;
            tileY += dy;
            if (plannedTiles == 2 && TileOccupied(tileX + dx, tileY + dy))
            {
                Level.ExecuteSpecial(87, self, null, false, polyId);
                state_ = 2;
            }
        }
        else if (unitsMoved >= plannedTiles * 64)
        {
            if (plannedTiles == 2)
            {
                int dx, dy;
                [dx, dy] = DirDelta(dirIdx);
                tileX += dx;
                tileY += dy;
            }
            state_ = 2;
        }
    }
}
