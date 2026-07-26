// Self-test hooks, active only when their CVARs are set (build.py --check).
//
// wolf_dbg_doortest: runs one full cycle on the map's first door and logs
// transition tics. Expected (charter DOOR-001/002 at 2 Wolf tics per engine
// tic): open = start+32, closing = open+150, closed = closing+32.
class WolfDebugHandler : EventHandler
{
    int phase;
    int t;
    bool found;
    WolfEnemySim sightEnemy;
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

        // pickup self-test: spawn a clip on the player, verify ammo + flags
        CVar pv = CVar.FindCVar("wolf_dbg_pickup");
        if (pv != null && pv.GetInt() != 0 && t == 30)
        {
            PlayerPawn pm = players[0].mo;
            Inventory am = pm.FindInventory("WolfAmmo");
            int before = am == null ? 0 : am.Amount;
            Actor it = Actor.Spawn("WolfStatic26", pm.pos);
            Console.Printf("WOLFDBG pickup: special=%d radius=%d",
                           it.bSpecial, int(it.radius));
            bool got = Inventory(it).CallTryPickup(pm);
            am = pm.FindInventory("WolfAmmo");
            int after = am == null ? 0 : am.Amount;
            Console.Printf("WOLFDBG pickup: got=%d ammo %d -> %d",
                           got, before, after);
        }

        // weapon soak: give the MG/chaingun and hold fire for 300 tics,
        // counting shots (catches refire recursion / cadence regressions)
        CVar wv = CVar.FindCVar("wolf_dbg_weapon");
        if (wv != null && wv.GetInt() != 0)
        {
            PlayerPawn pm = players[0].mo;
            if (t == 20)
            {
                pm.GiveInventoryType(wv.GetInt() == 2 ? "WolfChaingun"
                                                      : "WolfMachineGun");
                pm.GiveInventoryType("WolfAmmo");
                Inventory a = pm.FindInventory("WolfAmmo");
                if (a != null) a.Amount = 99;
                Console.Printf("WOLFDBG weapon soak: armed");
            }
            if (t == 80)
            {
                // kick the weapon into its Fire sequence; wolf_dbg_forcefire
                // keeps A_WolfRewind looping as if the button were held.
                // (Weapon switching takes ~40 tics, hence the delay.)
                Weapon w = players[0].ReadyWeapon;
                String rname = "none";
                if (w != null)
                    rname = String.Format("%s", w.GetClassName());
                Console.Printf("WOLFDBG weapon soak: ready=%s", rname);
                if (w != null)
                    players[0].SetPSprite(PSP_WEAPON, w.FindState("Fire"));
            }
            if (t == 320)
            {
                Inventory a = pm.FindInventory("WolfAmmo");
                int left = -1;
                if (a != null) { left = a.Amount; a.Amount = 0; }
                Console.Printf("WOLFDBG weapon soak: shots=%d tics=240",
                               99 - left);
            }
        }

        // exit self-test: teleport to the level's elevator switch, face it,
        // and use it; the next map's handler reports arrival.
        CVar xv = CVar.FindCVar("wolf_dbg_exit");
        if (xv != null && xv.GetInt() != 0 && t == 30)
        {
            WolfLevel wl = WolfLevel.Get();
            PlayerPawn pm = players[0].mo;
            if (wl != null && pm != null)
            {
                for (int ty = 0; ty < 64 && !found; ty++)
                for (int tx = 0; tx < 64 && !found; tx++)
                {
                    if (!wl.ElevatorAt(tx, ty))
                        continue;
                    // stand one tile west of the switch, facing east
                    if (wl.AreaAt(tx - 1, ty) < 0)
                        continue;
                    found = true;
                    pm.SetOrigin(((tx - 1) * 64 + 32,
                                  4096.0 - ((ty) * 64 + 32), 0), false);
                    pm.Angle = 0;
                    Console.Printf("WOLFDBG exit: at switch %d,%d on %s",
                                   tx, ty, Level.MapName);
                    WolfPlayer(pm).WolfUse();
                }
                if (!found)
                    Console.Printf("WOLFDBG exit: no usable switch");
            }
        }
        if (t == 3 || t == 120 || t == 240)
            Console.Printf("WOLFDBG onmap %s t=%d", Level.MapName, t);

        // sight self-test (CheckSight facing rule): park the player 3 tiles
        // east of a standing guard in the same area. Facing away => must NOT
        // wake; turned toward the player => must wake.
        CVar sv = CVar.FindCVar("wolf_dbg_sight");
        if (sv != null && sv.GetInt() != 0)
        {
            if (t == 400 && sightEnemy == null)
            {
                WolfLevel wl = WolfLevel.Get();
                ThinkerIterator it = ThinkerIterator.Create("WolfGuardStand");
                WolfEnemySim e;
                while ((e = WolfEnemySim(it.Next())) != null)
                {
                    int px = e.tileX + 3, py = e.tileY;
                    int st; WolfDoor dd;
                    [st, dd] = wl.TileState(px, py);
                    if (st != 0 || wl.AreaAt(px, py) != e.areanumber)
                        continue;
                    sightEnemy = e;
                    players[0].mo.SetOrigin((px * 64 + 32,
                        4096.0 - (py * 64 + 32), 0), false);
                    e.dir = 4;              // face WEST, player is east
                    e.temp2 = 0;
                    e.ambushFlag = false;
                    e.attackMode = false;   // baseline: asleep
                    e.activeFlag = false;
                    e.SetState_(e.StandState());
                    Console.Printf("WOLFDBG sight: armed at %d,%d "
                                   "(enemy %d,%d dir=%d atk=%d)",
                                   px, py, e.tileX, e.tileY, e.dir,
                                   e.attackMode);
                    break;
                }
                if (sightEnemy == null)
                    Console.Printf("WOLFDBG sight: no usable guard");
            }
            if (t == 405 && sightEnemy != null)
                Console.Printf("WOLFDBG sight: t45 dir=%d atk=%d sight=%d "
                               "noise=%d",
                               sightEnemy.dir, sightEnemy.attackMode,
                               sightEnemy.CheckSight_(),
                               WolfLevel.Get().madenoise);
            if (t == 520 && sightEnemy != null)
            {
                Console.Printf("WOLFDBG sight: facing-away attack=%d dir=%d",
                               sightEnemy.attackMode, sightEnemy.dir);
                sightEnemy.dir = 0;         // now face EAST, toward player
                sightEnemy.temp2 = 0;
            }
            if (t == 660 && sightEnemy != null)
                Console.Printf("WOLFDBG sight: facing-player attack=%d",
                               sightEnemy.attackMode);
        }

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
