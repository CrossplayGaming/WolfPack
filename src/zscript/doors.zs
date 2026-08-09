// WolfDoor — the WL_ACT1.C door state machine, run at Wolf-tic granularity
// (2 Wolf tics per engine tic, TIC-001) and driving a polyobject slab.
//
// Charter refs:
//   DOOR-001 auto-close OPENTICS=300 Wolf tics
//   DOOR-002 slide position += tics<<10 -> full 0..0xFFFF in 64 Wolf tics
//   DOOR-004 locked doors vs keys (keys land in Phase 2; locked = message)
//   DOOR-005 use while closing -> reopen; while opening -> close
//   DOOR-006 refuse to close on player/actor in or straddling the tile
//   DOOR-010 closing aborts -> reopen if something got inside
//   DOOR-007/008/009 area joins: Phase 2 sound-propagation sim
//
// The polyobject is moved with Polyobj_Move at a constant speed derived from
// the same constants, so the visible slab and the sim position agree:
// 1024 pos-units per Wolf tic = 1 map unit per Wolf tic = 2 units/engine tic.
class WolfDoor : Actor
{
    enum EDoorAction { DR_CLOSED, DR_OPENING, DR_OPEN, DR_CLOSING };

    int doorAction;
    int position;       // 0..0xFFFF, Wolf door units (doorposition[])
    int ticcount;       // Wolf tics spent open
    int polyId;
    bool vertical;
    int lock;           // 0 normal, 1-4 keyed, 5 elevator
    int tileX, tileY;   // Wolf tile coords
    int homeX, homeY;   // closed-position polyobject origin (start spot)
    bool areasJoined;   // DOOR-008/009 bookkeeping

    const OPENTICS = 300;           // WL_ACT1.C:270
    const FULLOPEN = 0xFFFF;
    const POSPERTIC = 1 << 10;      // WL_ACT1.C:593 (per Wolf tic)
    const MOVESPEED = 16;           // Polyobj_Move: 16/8 = 2 units/engine tic
    const SLIDEDIST = 64;           // one tile

    Default
    {
        +NOBLOCKMAP +NOSECTOR +NOINTERACTION +NOGRAVITY +DONTSPLASH
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        polyId  = args[0];
        vertical = args[1] != 0;
        lock    = args[2];
        // deathmatch: locked doors can't exist - keys are campaign drops
        // (the MAP09 gold key is Hans's), so a lock would seal the arena.
        // Here, not in the arena sweep: PostBeginPlay runs on the first
        // TICK, after WorldLoaded, and overwrote an earlier unlock there.
        if (deathmatch)
            lock = 0;
        tileX = int(pos.x) / 64;
        tileY = 63 - (int(pos.y) / 64);
        homeX = int(pos.x);
        homeY = int(pos.y);
        doorAction = DR_CLOSED;
        position = 0;
        ticcount = 0;
        FindGateLines();
        A_SetSolid(true);           // closed doors block the tile

    }

    // slide dir: vertical doors slide SOUTH (UDMF -y), horizontal EAST (+x)
    // (WL_DRAW.C:625,693 — slab moves toward increasing world coordinate).
    // Movement uses Polyobj_MoveTo with ABSOLUTE targets so the slab can
    // never drift from the sim position across interrupted cycles.
    int OpenX() { return vertical ? homeX : homeX + SLIDEDIST; }
    int OpenY() { return vertical ? homeY - SLIDEDIST : homeY; }

    // The door tile is solid until fully open (actorat, WL_ACT1.C:599-602).
    // Blocking is done with the tile's two entrance lines rather than a
    // solid actor: an actor at the tile centre stands in the sliding
    // slab's path and stalls the polyobject until it is cleared.
    Array<Line> gateLines;

    void FindGateLines()
    {
        double cx = tileX * 64 + 32, cy = (63 - tileY) * 64 + 32;
        for (int i = 0; i < Level.Lines.Size(); i++)
        {
            Line l = Level.Lines[i];
            if (l.sidedef[1] == null)
                continue;                   // one-sided: already a wall
            Vector2 mid = (l.v1.p + l.v2.p) / 2;
            // the two edges perpendicular to the slide axis
            if (vertical)
            {
                if (abs(mid.y - cy) < 1
                    && (abs(mid.x - (cx - 32)) < 1
                        || abs(mid.x - (cx + 32)) < 1))
                    gateLines.Push(l);
            }
            else
            {
                if (abs(mid.x - cx) < 1
                    && (abs(mid.y - (cy - 32)) < 1
                        || abs(mid.y - (cy + 32)) < 1))
                    gateLines.Push(l);
            }
        }
    }

    void A_SetSolid(bool on)
    {
        for (int i = 0; i < gateLines.Size(); i++)
        {
            if (on)
                gateLines[i].flags |= Line.ML_BLOCKING;
            else
                gateLines[i].flags &= ~Line.ML_BLOCKING;
        }
    }

    // areas on both sides (DOOR-011: vertical x+-1, horizontal y+-1)
    int, int SideAreas(WolfLevel wl)
    {
        if (vertical)
            return wl.AreaAt(tileX - 1, tileY), wl.AreaAt(tileX + 1, tileY);
        return wl.AreaAt(tileX, tileY - 1), wl.AreaAt(tileX, tileY + 1);
    }

    // OperateDoor (WL_ACT1.C:498-522)
    void Operate(Actor user)
    {
        if (lock >= 1 && lock <= 4)
        {
            // DOOR-004: gamestate.keys & (1 << (lock-1))
            String need = lock == 1 ? "WolfGoldKey" : "WolfSilverKey";
            if (user == null || user.FindInventory(need) == null)
            {
                if (user != null)
                    user.A_StartSound("wolf/noway", CHAN_VOICE);
                if (user && user.player)
                    user.A_Log(lock == 1 ? "You need a gold key"
                                         : "You need a silver key");
                return;
            }
        }
        switch (doorAction)
        {
        case DR_CLOSED:
        case DR_CLOSING:
            StartOpen();
            break;
        case DR_OPEN:
        case DR_OPENING:
            StartClose(false);
            break;
        }
    }

    // OpenDoor (WL_ACT1.C:400-406)
    void StartOpen()
    {
        if (doorAction == DR_OPEN)
        {
            ticcount = 0;
            return;
        }
        if (doorAction == DR_OPENING)
            return;
        A_StartSound("wolf/dooropen", CHAN_AUTO, attenuation: 1.0);
        Level.ExecuteSpecial(87, self, null, false, polyId);   // Polyobj_Stop
        Level.ExecuteSpecial(88, self, null, false,            // Polyobj_MoveTo
                             polyId, MOVESPEED, OpenX(), OpenY());
        doorAction = DR_OPENING;
        if (!areasJoined)          // just left fully closed: join areas
        {
            WolfLevel wl = WolfLevel.Get();
            if (wl != null)
            {
                int a1, a2;
                [a1, a2] = SideAreas(wl);
                wl.DoorConnect(a1, a2, 1);
            }
            areasJoined = true;
        }
    }

    // CloseDoor checks (WL_ACT1.C:417-460): refuse if blocked
    bool TileBlocked()
    {
        // CloseDoor's FIRST test is `if (actorat[tilex][tiley]) return;`
        // (WL_ACT1.C:425) - the sim's tile claim, which an actor takes
        // on its DESTINATION tile the instant TryWalk grants the move,
        // a whole tile before it arrives there. Testing only where
        // bodies physically are (below) misses exactly that window, so
        // a door could shut on an enemy already committed to walking
        // through it, and the enemy then crossed a closed door (user
        // report: back out, door closes, enemy comes through it).
        WolfLevel wlv = WolfLevel.Get();
        if (wlv != null && wlv.ActorAt(tileX, tileY) != null)
            return true;
        // anything shootable (or a player) whose bounding box overlaps the
        // door tile, expanded by MINDIST (0x5800 -> 22 units) per DOOR-006
        double x1 = tileX * 64 - 22, x2 = tileX * 64 + 64 + 22;
        double y1 = (63 - tileY) * 64 - 22, y2 = (63 - tileY) * 64 + 64 + 22;
        // limit the straddle margin to the door's axis, like the source
        if (vertical) { y1 += 22; y2 -= 22; }
        else          { x1 += 22; x2 -= 22; }
        ThinkerIterator it = ThinkerIterator.Create("Actor");
        Actor a;
        while ((a = Actor(it.Next())) != null)
        {
            if (!a.bShootable && !a.player)
                continue;
            if (a.pos.x + a.radius <= x1 || a.pos.x - a.radius >= x2)
                continue;
            if (a.pos.y + a.radius <= y1 || a.pos.y - a.radius >= y2)
                continue;
            return true;
        }
        return false;
    }

    void StartClose(bool autoClose)
    {
        if (TileBlocked())
        {
            if (autoClose)
                ticcount = 0;      // retry later, door stays open
            return;
        }
        A_SetSolid(true);           // closing: the tile blocks again
        A_StartSound("wolf/doorclose", CHAN_AUTO, attenuation: 1.0);
        Level.ExecuteSpecial(87, self, null, false, polyId);
        Level.ExecuteSpecial(88, self, null, false,
                             polyId, MOVESPEED, homeX, homeY);
        doorAction = DR_CLOSING;
    }

    override void Tick()
    {
        Super.Tick();
        WolfTic();
        WolfTic();
    }

    // one 1/70s step of MoveDoors/DoorOpening/DoorClosing
    void WolfTic()
    {
        switch (doorAction)
        {
        case DR_OPENING:
            position += POSPERTIC;
            if (position >= FULLOPEN)
            {
                position = FULLOPEN;
                doorAction = DR_OPEN;
                ticcount = 0;
                A_SetSolid(false);      // actorat cleared: tile passable
            }
            break;
        case DR_OPEN:
            ticcount++;
            if (ticcount >= OPENTICS)
                StartClose(true);
            break;
        case DR_CLOSING:
            if (TileBlocked())          // DOOR-010: something got inside
            {
                StartOpen();
                break;
            }
            position -= POSPERTIC;
            if (position <= 0)
            {
                position = 0;
                doorAction = DR_CLOSED;
                if (areasJoined)   // fully closed: disconnect areas
                {
                    WolfLevel wl = WolfLevel.Get();
                    if (wl != null)
                    {
                        int a1, a2;
                        [a1, a2] = SideAreas(wl);
                        wl.DoorConnect(a1, a2, -1);
                    }
                    areasJoined = false;
                }
            }
            break;
        default:
            break;
        }
    }
}
