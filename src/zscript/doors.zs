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
        tileX = int(pos.x) / 64;
        tileY = 63 - (int(pos.y) / 64);
        doorAction = DR_CLOSED;
        position = 0;
        ticcount = 0;
    }

    // slide angle: vertical doors slide SOUTH (270), horizontal EAST (0)
    // (WL_DRAW.C:625,693 — slab moves toward increasing world coordinate)
    int SlideAngleByte() { return vertical ? 192 : 0; }
    int ReturnAngleByte() { return vertical ? 64 : 128; }

    // OperateDoor (WL_ACT1.C:498-522)
    void Operate(Actor user)
    {
        if (lock >= 1 && lock <= 4)
        {
            // DOOR-004: key check lands with the Phase 2 key items
            if (user && user.player)
                user.A_Log("This door is locked. (keys arrive in Phase 2)");
            return;
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
        int remaining = (FULLOPEN - position) / POSPERTIC;      // map units
        Level.ExecuteSpecial(4, self, null, false,              // Polyobj_Move
                             polyId, MOVESPEED, SlideAngleByte(),
                             Max(remaining, 1));
        doorAction = DR_OPENING;
    }

    // CloseDoor checks (WL_ACT1.C:417-460): refuse if blocked
    bool TileBlocked()
    {
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
        A_StartSound("wolf/doorclose", CHAN_AUTO, attenuation: 1.0);
        Level.ExecuteSpecial(87, self, null, false, polyId);
        int back = position / POSPERTIC;
        Level.ExecuteSpecial(4, self, null, false,
                             polyId, MOVESPEED, ReturnAngleByte(),
                             Max(back, 1));
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
            }
            break;
        default:
            break;
        }
    }
}
