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
    bool sightWakeDone;
    int blockProbe;
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
        // hunt actors rendering the missing-sprite marker (user report:
        // a floating alert icon in SP). "Unknown" is the engine's class
        // for unrecognized editor numbers.
        if (t == 10)
        {
            ThinkerIterator uit = ThinkerIterator.Create("Actor");
            Actor ua;
            while ((ua = Actor(uit.Next())) != null)
            {
                if (ua is "Unknown" || ua.GetClassName() == "Unknown")
                    Console.Printf("WOLFDBG unknown-thing at (%d,%d) tile "
                                   "%d,%d", int(ua.pos.x), int(ua.pos.y),
                                   int(ua.pos.x) / 64,
                                   63 - (int(ua.pos.y) / 64));
            }
        }

        CVar apv = CVar.FindCVar("wolf_dbg_check");
        if (t == 12 && apv != null && apv.GetInt() != 0)
            Console.Printf("WOLFDBG allow: jump=%d crouch=%d freelook=%d",
                           Level.IsJumpingAllowed(),
                           Level.IsCrouchingAllowed(),
                           Level.IsFreelookAllowed());

        // jump probe: hold BT_JUMP via cmd injection for a few tics, then
        // report every CheckJump precondition plus the resulting Vel.Z
        CVar jpv = CVar.FindCVar("wolf_dbg_jump");
        if (jpv != null && jpv.GetInt() != 0 && players[0].mo != null)
        {
            PlayerPawn pm = players[0].mo;
            // WorldTick runs after PlayerThink consumed this tic's cmd, and
            // next tic the net stream overwrites it - so drive CheckJump
            // directly with the button set, same code path a real press hits
            if (t == 22)
            {
                players[0].cmd.buttons |= BT_JUMP;
                pm.CheckJump();
            }
            if (t == 21 || t == 24)
                Console.Printf("WOLFDBG jump t=%d: onground=%d jumpTics=%d "
                               "crouchoff=%f water=%d nograv=%d JumpZ=%f "
                               "velz=%f z=%f floorz=%f",
                               t, players[0].onground, players[0].jumpTics,
                               players[0].crouchoffset, pm.waterlevel,
                               pm.bNoGravity, pm.JumpZ, pm.Vel.Z,
                               pm.pos.z, pm.floorz);
            if (t == 40)
                Console.Printf("WOLFDBG jump result: z=%f (spawn floor %f)",
                               pm.pos.z, pm.floorz);
        }

        // net-sync beacon: same line must appear in every node's log at
        // the same tic - any field difference is a lockstep divergence
        CVar nbv = CVar.FindCVar("wolf_dbg_net");
        if (nbv != null && nbv.GetInt() != 0 && t % 30 == 0)
        {
            WolfLevel nwl = WolfLevel.Get();
            String hp = "";
            for (int p = 0; p < MAXPLAYERS; p++)
                if (playeringame[p] && players[p].mo != null)
                    hp = hp .. String.Format(" p%d:h=%d,x=%d,y=%d", p,
                        players[p].mo.health,
                        int(players[p].mo.pos.x * 4),
                        int(players[p].mo.pos.y * 4));
            Console.Printf("WOLFDBG net t=%d rng=%d%s", t,
                           nwl == null ? -1 : nwl.rngIndex, hp);
        }

        // deathmatch door-lock probe: after PostBeginPlay has run (first
        // tick), every door in a DM arena must read unlocked
        if (apv != null && apv.GetInt() != 0 && t == 30 && deathmatch)
        {
            int locked = 0;
            ThinkerIterator ddit = ThinkerIterator.Create("WolfDoor");
            WolfDoor dd;
            while ((dd = WolfDoor(ddit.Next())) != null)
                if (dd.lock != 0)
                    locked++;
            Console.Printf("WOLFDBG arena doors still locked: %d", locked);
        }

        // lobby-flow probe: warp player 0 through a west band (episode),
        // an east band (skill), then Hans's chamber (commit) and confirm
        // the level changes to the chosen episode at the chosen skill
        CVar lbv = CVar.FindCVar("wolf_dbg_lobby");
        if (lbv != null && lbv.GetInt() != 0 && players[0].mo != null
            && Level.MapName ~== "LOBBY")
        {
            PlayerPawn pm = players[0].mo;
            if (t == 30)
                pm.SetOrigin((27 * 64 + 32, (63 - 30) * 64 + 32,
                              pm.floorz), false);       // west band 2 = E3
            if (t == 60)
                pm.SetOrigin((41 * 64 + 32, (63 - 22) * 64 + 32,
                              pm.floorz), false);       // east band 0 = S1
            if (t == 90)
                pm.SetOrigin((34 * 64 + 32, (63 - 12) * 64 + 32,
                              pm.floorz), false);       // chamber = commit
        }
        if (lbv != null && lbv.GetInt() != 0 && t == 150)
            Console.Printf("WOLFDBG lobby: map=%s skill=%d",
                           Level.MapName, G_SkillPropertyInt(SKILLP_ACSReturn));

        // uniform-recolor probe: with wolf_skin set, the player's sprite
        // must be the variant stand sprite, not the grey BJ1S
        CVar skv = CVar.FindCVar("wolf_dbg_skin");
        if (skv != null && skv.GetInt() != 0 && t == 30
            && players[0].mo != null)
        {
            PlayerPawn pm = players[0].mo;
            CVar sc = CVar.GetCVar("wolf_skin", players[0]);
            int v = sc == null ? 0 : sc.GetInt();
            int expect = Actor.GetSpriteIndex(
                v == 1 ? 'BJ2S' : v == 2 ? 'BJ3S'
                                : v == 3 ? 'BJ4S' : 'BJ1S');
            Console.Printf("WOLFDBG skin: wolf_skin=%d sprite=%d expect=%d "
                           "%s", v, pm.sprite, expect,
                           pm.sprite == expect ? "OK" : "MISMATCH");
        }

        // map-load heartbeat the harness greps for. Gated: without this it
        // prints over the screen during ordinary play.
        if (t == 3 || t == 120 || t == 240)
        {
            CVar cv = CVar.FindCVar("wolf_dbg_check");
            if (cv != null && cv.GetInt() != 0)
                Console.Printf("WOLFDBG onmap %s t=%d", Level.MapName, t);
        }

        // sight self-test (CheckSight facing rule): park the player 3 tiles
        // east of a standing guard in the same area. Facing away => must NOT
        // wake; turned toward the player => must wake.
        CVar sv = CVar.FindCVar("wolf_dbg_sight");
        if (sv != null && sv.GetInt() != 0)
        {
            if (t == 400 && sightEnemy == null)
            {
                WolfLevel wl = WolfLevel.Get();
                // only guards in the PLAYER'S OWN area: SightPlayer's
                // areabyplayer gate follows door connectivity, not
                // teleports, so a guard behind unopened doors can never
                // wake - which made this test pick-dependent and flaky
                PlayerPawn pp = players[0].mo;
                int parea = wl.AreaAt(int(pp.pos.x) / 64,
                                      63 - (int(pp.pos.y) / 64));
                ThinkerIterator it = ThinkerIterator.Create("WolfGuardStand");
                WolfEnemySim e;
                while ((e = WolfEnemySim(it.Next())) != null)
                {
                    if (e.areanumber != parea)
                        continue;
                    int px = e.tileX + 3, py = e.tileY;
                    int st; WolfDoor dd;
                    [st, dd] = wl.TileState(px, py);
                    if (st != 0 || wl.AreaAt(px, py) != e.areanumber)
                        continue;
                    sightEnemy = e;
                    players[0].mo.SetOrigin((px * 64 + 32,
                        4096.0 - (py * 64 + 32), 0), false);
                    // harness artifact: the woken guard can kill the
                    // player before the check, restarting the floor and
                    // wiping the test - THE flaky-gate cause
                    players[0].mo.bINVULNERABLE = true;
                    // and the test subject: the weapon-soak test sprays
                    // rounds on this same floor, and a corpse never wakes
                    e.bINVULNERABLE = true;
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
            // latched poll, not a fixed deadline: the reaction delay is
            // RANDOM (REACT-001..006), so pass the moment the wake lands
            // and fail only after a generous window
            if (t > 522 && t <= 940 && sightEnemy != null && !sightWakeDone)
            {
                if (sightEnemy.attackMode)
                {
                    sightWakeDone = true;
                    Console.Printf("WOLFDBG sight: facing-player attack=1");
                }
                else if (t == 940)
                    Console.Printf("WOLFDBG sight: facing-player attack=0 "
                                   "hp=%d", sightEnemy.health);
            }
        }

        // death self-test: damage the player to death, then watch the
        // sequence run and the floor restart with the pistol loadout.
        CVar dv = CVar.FindCVar("wolf_dbg_death");
        if (dv != null && dv.GetInt() != 0)
        {
            PlayerPawn pm = players[0].mo;
            if (t == 40 && pm != null)
            {
                WolfGameState gs = WolfGameState.Get();
                if (gs != null)
                    gs.score[0] = 12345;       // must roll back on restart
                pm.A_GiveInventory("WolfMachineGun");
                Console.Printf("WOLFDBG death: killing player (lives=%d)",
                               gs == null ? -99 : gs.lives[0]);
                pm.DamageMobj(null, null, 500, 'Bullet', DMG_THRUSTLESS);
            }
            if ((t == 60 || t == 130 || t == 200) && pm != null)
                Console.Printf("WOLFDBG death: t=%d phase=%d timer=%d",
                               t, WolfPlayer(pm).deathPhase,
                               WolfPlayer(pm).deathTimer);
            if (t == 6)
            {
                WolfGameState gs = WolfGameState.Get();
                PlayerPawn p2 = players[0].mo;
                bool mg = p2 != null
                    && p2.FindInventory("WolfMachineGun") != null;
                Inventory am = p2 == null ? null
                                          : p2.FindInventory("WolfAmmo");
                Console.Printf("WOLFDBG death: onload lives=%d score=%d "
                               "mg=%d ammo=%d",
                               gs == null ? -99 : gs.lives[0],
                               gs == null ? -99 : gs.score[0],
                               mg, am == null ? -1 : am.Amount);
            }
        }

        // wolf_dbg_arm: hand the player the full arsenal at level start
        // (boss playtesting � see boss.bat)
        CVar armv = CVar.FindCVar("wolf_dbg_arm");
        if (armv != null && armv.GetInt() != 0 && t == 2)
        {
            PlayerPawn pm = players[0].mo;
            if (pm != null)
            {
                pm.GiveInventoryType("WolfMachineGun");
                pm.GiveInventoryType("WolfChaingun");
                pm.GiveInventoryType("WolfGoldKey");
                pm.GiveInventoryType("WolfSilverKey");
                Inventory a = pm.FindInventory("WolfAmmo");
                if (a != null) a.Amount = 99;
                Console.Printf("WOLFDBG armed: chaingun, MG, 99 ammo, keys");
                // one-shot: zero the cvar so the value archived at exit
                // can never arm a later session (the ini leak, round 3)
                armv.SetInt(0);
            }
        }

        // victory-run self-test: stand on a victory tile
        CVar vv = CVar.FindCVar("wolf_dbg_victory");
        if (vv != null && vv.GetInt() != 0)
        {
            if (t == 40)
            {
                ThinkerIterator vit =
                    ThinkerIterator.Create("WolfVictoryTrigger");
                WolfMarker vm = WolfMarker(vit.Next());
                PlayerPawn pm = players[0].mo;
                if (vm != null && pm != null)
                {
                    pm.SetOrigin((vm.tileX * 64 + 32,
                                  4096.0 - (vm.tileY * 64 + 32), 0), false);
                    pm.Angle = 90;          // face NORTH: the spin must
                                            // turn us around by itself
                    Console.Printf("WOLFDBG victory: on tile %d,%d",
                                   vm.tileX, vm.tileY);
                }
                else
                    Console.Printf("WOLFDBG victory: no tile on this map");
            }
            if (t == 60 || t == 150)
            {
                ThinkerIterator bit = ThinkerIterator.Create("WolfBJVictory");
                Actor bj = Actor(bit.Next());
                PlayerPawn pv = players[0].mo;
                Console.Printf("WOLFDBG victory: t=%d bj=%d ang=%d py=%d",
                               t, bj != null, int(pv.Angle), int(pv.pos.y));
            }
        }

        // boss self-test: kill the boss outright and watch the DeathCam
        CVar bv = CVar.FindCVar("wolf_dbg_boss");
        if (bv != null && bv.GetInt() != 0)
        {
            if (t == 40)
            {
                ThinkerIterator bit = ThinkerIterator.Create("WolfBoss");
                WolfEnemySim b = WolfEnemySim(bit.Next());
                if (b != null)
                {
                    Console.Printf("WOLFDBG boss: %s hp=%d -> killing",
                                   b.GetClassName(), b.hitpoints);
                    b.DamageMobj(players[0].mo, players[0].mo, 9999,
                                 'Bullet', DMG_THRUSTLESS);
                }
                else
                    Console.Printf("WOLFDBG boss: none found");
            }
            if (t == 70 || t == 200 || t == 330)
            {
                WolfDeathCam cam = WolfDeathCam.Get();
                WolfGameState gs = WolfGameState.Get();
                Console.Printf("WOLFDBG boss: t=%d camphase=%d victory=%d",
                               t, cam == null ? -1 : cam.phase,
                               gs == null ? -1 : gs.victoryFlag);
            }
        }

        if (phase > 4)
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
            // barrier probe: a closed door tile must block the player,
            // an open one must not (actorat semantics, WL_ACT1.C:599-602)
            PlayerPawn pm = players[0].mo;
            Vector3 doorPos = (door.tileX * 64 + 32,
                               4096.0 - (door.tileY * 64 + 32), 0);
            int ax = door.vertical ? door.tileX - 1 : door.tileX;
            int ay = door.vertical ? door.tileY : door.tileY - 1;
            pm.SetOrigin((ax * 64 + 32, 4096.0 - (ay * 64 + 32), 0), false);
            bool blockedClosed = !pm.TryMove(doorPos.xy, 0, false);
            door.StartOpen();
            blockProbe = blockedClosed ? 1 : 0;
            phase = 4;
        }
        else if (phase == 4 && door.doorAction == WolfDoor.DR_OPEN)
        {
            PlayerPawn pm2 = players[0].mo;
            Vector2 dp = (door.tileX * 64 + 32,
                          4096.0 - (door.tileY * 64 + 32));
            bool passOpen = pm2.TryMove(dp, 0, false);
            Console.Printf("DOORTEST barrier closed_blocks=%d open_passes=%d",
                           blockProbe, passOpen);
            phase = 5;
        }
    }
}
