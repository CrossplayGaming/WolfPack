// Self-test hooks, active only when their CVARs are set (build.py --check).
//
// wolf_dbg_doortest: runs one full cycle on the map's first door and logs
// transition tics. Expected (charter DOOR-001/002 at 2 Wolf tics per engine
// tic): open = start+32, closing = open+150, closed = closing+32.
class WolfDebugHandler : EventHandler
{
    int phase;
    int t;
    WolfDoor door;

    override void WorldTick()
    {
        if (phase > 3)
            return;
        CVar cv = CVar.FindCVar("wolf_dbg_doortest");
        if (cv == null || cv.GetInt() == 0)
            return;
        t++;
        if (phase == 0 && t >= 10)
        {
            ThinkerIterator it = ThinkerIterator.Create("WolfDoor");
            door = WolfDoor(it.Next());
            if (door == null)
            {
                Console.Printf("DOORTEST nodoors");
                phase = 4;
                return;
            }
            Console.Printf("DOORTEST start %d", t);
            door.Operate(players[0].mo);
            phase = 1;
        }
        else if (phase == 1 && door.doorAction == WolfDoor.DR_OPEN)
        {
            Console.Printf("DOORTEST open %d", t);
            phase = 2;
        }
        else if (phase == 2 && door.doorAction == WolfDoor.DR_CLOSING)
        {
            Console.Printf("DOORTEST closing %d", t);
            phase = 3;
        }
        else if (phase == 3 && door.doorAction == WolfDoor.DR_CLOSED)
        {
            Console.Printf("DOORTEST closed %d", t);
            phase = 4;
        }
    }
}
