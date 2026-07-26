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
        t++;
        // forced-alert soak: wolf_dbg_alert 1 puts every enemy in chase
        CVar av = CVar.FindCVar("wolf_dbg_alert");
        if (av != null && av.GetInt() != 0 && t == 40)
        {
            ThinkerIterator ait = ThinkerIterator.Create("WolfEnemySim");
            WolfEnemySim ae;
            int na = 0;
            while ((ae = WolfEnemySim(ait.Next())) != null)
            {
                if (!ae.attackMode) { ae.FirstSighting(); na++; }
            }
            Console.Printf("WOLFDBG alerted %d enemies", na);
        }
        if (av != null && av.GetInt() != 0 && t == 200)
            Console.Printf("WOLFDBG alert soak survived to tic 200");

        if (phase > 3)
            return;
        CVar cv = CVar.FindCVar("wolf_dbg_doortest");
        if (cv == null || cv.GetInt() == 0)
            return;
        if (phase == 0 && t == 5)
        {
            // enemy census + sprite sanity
            int n = 0, vis = 0;
            ThinkerIterator eit = ThinkerIterator.Create("WolfEnemySim");
            WolfEnemySim en;
            WolfEnemySim first = null;
            while ((en = WolfEnemySim(eit.Next())) != null)
            {
                n++;
                if (first == null) first = en;
            }
            Console.Printf("WOLFDBG census: skill=%d enemies=%d",
                           G_SkillPropertyInt(SKILLP_ACSReturn), n);
            if (first != null)
                Console.Printf("WOLFDBG first: spr=%d frm=%d pos=(%d,%d) st=%d",
                               first.sprite, first.frame, int(first.pos.x),
                               int(first.pos.y), first.stateIdx);
        }
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
