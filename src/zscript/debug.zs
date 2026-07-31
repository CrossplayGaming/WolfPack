// Self-test hooks, active only when their CVARs are set (build.py --check).
//
// wolf_dbg_doortest: runs one full cycle on the map's first door and logs
// transition tics. Expected (charter DOOR-001/002 at 2 Wolf tics per engine
// tic): open = start+32, closing = open+150, closed = closing+32.
class WolfDebugHandler : EventHandler
{
    // probe helper: `netevent wolf_dbg_face <deg>` points the sender's
    // pawn - headless exit/door probes need an exact facing and the
    // console has no angle command
    override void NetworkProcess(ConsoleEvent e)
    {
        if (e.Name == "wolf_dbg_face" && e.Player >= 0
            && players[e.Player].mo != null)
            players[e.Player].mo.angle = e.Args[0];
        // dump the sector planes under the sender - flats debugging
        if (e.Name == "wolf_dbg_flatcheck" && e.Player >= 0
            && players[e.Player].mo != null)
        {
            Sector sc = players[e.Player].mo.CurSector;
            Console.Printf("FLATCHECK sec=%d floor=%s ceil=%s",
                sc.Index(),
                TexMan.GetName(sc.GetTexture(Sector.floor)),
                TexMan.GetName(sc.GetTexture(Sector.ceiling)));
        }
        // set the exiting latch as if an elevator had been used - for
        // proving field persistence across level travel
        if (e.Name == "wolf_dbg_setexit" && e.Player >= 0
            && players[e.Player].mo != null)
        {
            let px = WolfPlayer(players[e.Player].mo);
            if (px != null) px.exiting = true;
        }
        // direct WolfUse invocation, bypassing the button edge detect
        if (e.Name == "wolf_dbg_use" && e.Player >= 0
            && players[e.Player].mo != null)
        {
            let pm2 = WolfPlayer(players[e.Player].mo);
            if (pm2 != null) pm2.WolfUse();
        }
        // one-shot dump of the WolfUse decision chain from the sender's
        // exact position - every gate the elevator branch must pass
        if (e.Name == "wolf_dbg_usecheck" && e.Player >= 0
            && players[e.Player].mo != null)
        {
            let pm = WolfPlayer(players[e.Player].mo);
            if (pm == null) return;
            double a = pm.angle % 360.0;
            if (a < 0) a += 360.0;
            int tx = int(pm.pos.x) / 64;
            int ty = 63 - (int(pm.pos.y) / 64);
            int cx = tx, cy = ty, dir;
            if (a < 45.0 || a >= 315.0)      { cx++; dir = 0; }
            else if (a < 135.0)              { cy--; dir = 1; }
            else if (a < 225.0)              { cx--; dir = 2; }
            else                             { cy++; dir = 3; }
            Console.Printf("USECHECK pos=(%d,%d) a=%.1f target=(%d,%d) "
                           "dir=%d", tx, ty, a, cx, cy, dir);
            ThinkerIterator it = ThinkerIterator.Create("WolfDoor");
            WolfDoor d;
            while ((d = WolfDoor(it.Next())) != null)
                if (d.tileX == cx && d.tileY == cy)
                    Console.Printf("USECHECK door CLAIMS target (lock=%d)",
                                   d.lock);
            WolfLevel wl = WolfLevel.Get();
            Console.Printf("USECHECK elevAt=%d areaAt(stand)=%d "
                           "exiting=%d", wl != null && wl.ElevatorAt(cx, cy),
                           wl == null ? -99 : wl.AreaAt(tx, ty),
                           pm.exiting);
        }
    }

    int phase;
    int t;
    bool found;
    WolfEnemySim sightEnemy;
    bool sightWakeDone;
    int blockProbe;
    WolfDoor door;

    // joiner menu-close repro (user report: Esc menu "blinks" shut for
    // the JOINING player in a real netgame): open the menu from ui scope
    // and watch whether it survives
    ui int menuProbeT;
    override void UiTick()
    {
        CVar mv = CVar.FindCVar("wolf_dbg_menutest");
        if (mv == null || mv.GetInt() == 0)
            return;
        menuProbeT++;
        if (menuProbeT == 300)
        {
            Menu.SetMenu("MainMenu");
            Console.Printf("WOLFDBG menutest: opened on player %d",
                           consoleplayer);
        }
        if (menuProbeT == 330 || menuProbeT == 500)
        {
            Menu cur = Menu.GetCurrentMenu();
            String cn = cur == null ? "NONE"
                : String.Format("%s", cur.GetClassName());
            Console.Printf("WOLFDBG menutest t=%d: current=%s",
                           menuProbeT, cn);
        }
    }

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

        // scripted netgame kill: deterministic (runs identically on all
        // nodes), exercises death -> cooldown -> auto-respawn
        CVar kv = CVar.FindCVar("wolf_dbg_kill");
        if (kv != null && kv.GetInt() != 0 && t == 100
            && playeringame[1] && players[1].mo != null)
        {
            players[1].mo.GiveInventoryType("WolfChaingun");
            players[1].mo.DamageMobj(players[0].mo, players[0].mo,
                                     300, 'Normal');
        }
        if (kv != null && kv.GetInt() != 0 && t == 140 && deathmatch)
        {
            int gats = 0, clips = 0, meds = 0, mgs = 0;
            ThinkerIterator pit = ThinkerIterator.Create("Actor");
            Actor pa;
            while ((pa = Actor(pit.Next())) != null)
            {
                String cn = String.Format("%s", pa.GetClassName());
                if (cn == "WolfStatic28") gats++;
                else if (cn == "WolfStatic27") mgs++;
                else if (cn == "WolfStatic26") clips++;
                else if (cn == "WolfStatic25") meds++;
            }
            Console.Printf("WOLFDBG dmitems: gatling=%d mg=%d clip=%d "
                           "medkit=%d", gats, mgs, clips, meds);
        }
        if (kv != null && kv.GetInt() != 0 && t == 150)
        {
            WolfLobby lb = WolfLobby(EventHandler.Find("WolfLobby"));
            if (lb != null)
                Console.Printf("WOLFDBG feed: n=%d last=[%s]",
                               lb.feed.Size(),
                               lb.feed.Size() ? lb.feed[lb.feed.Size()-1]
                                              : "");
        }

        // font-identity probe: which font is SmallFont now?
        CVar fpv = CVar.FindCVar("wolf_dbg_font");
        if (fpv != null && fpv.GetInt() != 0 && t == 12)
        {
            Font sf = Font.GetFont("SmallFont");
            Font wp = Font.GetFont("wolfprop");
            Font cf = Font.GetFont("ConsoleFont");
            Console.Printf("WOLFDBG fonts: small W=%d h=%d | wolfprop W=%d "
                           "h=%d | console W=%d h=%d",
                sf == null ? -1 : sf.StringWidth("W"),
                sf == null ? -1 : sf.GetHeight(),
                wp == null ? -1 : wp.StringWidth("W"),
                wp == null ? -1 : wp.GetHeight(),
                cf == null ? -1 : cf.StringWidth("W"),
                cf == null ? -1 : cf.GetHeight());
            Font nsf = Font.GetFont("NewSmallFont");
            Font ncf = Font.GetFont("NewConsoleFont");
            Console.Printf("WOLFDBG fonts2: newsmall W=%d h=%d | "
                           "newconsole W=%d h=%d",
                nsf == null ? -1 : nsf.StringWidth("W"),
                nsf == null ? -1 : nsf.GetHeight(),
                ncf == null ? -1 : ncf.StringWidth("W"),
                ncf == null ? -1 : ncf.GetHeight());
        }

        // Pac-Man ghost probe: with wolf_dbg_alert waking everything,
        // ghosts must chase (position changes) and drain on touch
        CVar gpv = CVar.FindCVar("wolf_dbg_ghost");
        if (gpv != null && gpv.GetInt() != 0)
        {
            if (t == 40)
            {
                ThinkerIterator wit = ThinkerIterator.Create("WolfGhost");
                WolfEnemySim wg;
                while ((wg = WolfEnemySim(wit.Next())) != null)
                    if (!wg.attackMode)
                        wg.FirstSighting();
            }
            if (t == 60 || t == 150)
            {
                ThinkerIterator git = ThinkerIterator.Create("WolfGhost");
                WolfEnemySim g;
                int n = 0;
                while ((g = WolfEnemySim(git.Next())) != null)
                {
                    n++;
                    if (n == 1)
                        Console.Printf("WOLFDBG ghost t=%d: pos=%d,%d "
                                       "speed=%d attackMode=%d", t,
                                       int(g.pos.x), int(g.pos.y),
                                       g.wolfSpeed, g.attackMode);
                }
                if (t == 60)
                    Console.Printf("WOLFDBG ghosts on map: %d", n);
            }
            if (t == 155 && players[0].mo != null)
                players[0].mo.health = 5000;    // survive the drain test
            if (t == 160 && players[0].mo != null)
            {
                ThinkerIterator git = ThinkerIterator.Create("WolfGhost");
                Actor g = Actor(git.Next());
                if (g != null)
                    players[0].mo.SetOrigin((g.pos.x + 40, g.pos.y,
                                             g.floorz), false);
            }
            if (t == 165 || t == 230)
            {
                ThinkerIterator git2 = ThinkerIterator.Create("WolfGhost");
                WolfEnemySim g2 = WolfEnemySim(git2.Next());
                WolfLevel wl2 = WolfLevel.Get();
                Console.Printf("WOLFDBG ghost touch t=%d: health=%d "
                               "gdist=%d dir=%d distance=%d stateIdx=%d "
                               "tc=%d", t,
                               players[0].mo.health,
                               g2 == null ? -1
                                   : int(g2.Distance2D(players[0].mo)),
                               g2 == null ? -1 : g2.dir,
                               g2 == null ? -1 : g2.distance,
                               g2 == null ? -1 : g2.stateIdx,
                               g2 == null ? -1 : g2.ticcount);
            }
        }

        // extra-boss probe: kill every Hans on the map through the sim's
        // own death path; the floor must survive (no deathcam, no exit)
        // and each must drop his gold key
        CVar bkv = CVar.FindCVar("wolf_dbg_bosskill");
        if (bkv != null && bkv.GetInt() != 0)
        {
            if (t == 60)
            {
                ThinkerIterator hit = ThinkerIterator.Create("WolfHans");
                WolfEnemySim h;
                int nh = 0;
                while ((h = WolfEnemySim(hit.Next())) != null)
                {
                    h.KillActor_(players[0].mo);
                    nh++;
                }
                Console.Printf("WOLFDBG bosskill: killed %d Hans", nh);
            }
            if (t == 260)
            {
                int keys = 0;
                ThinkerIterator kit = ThinkerIterator.Create("Actor");
                Actor a;
                while ((a = Actor(kit.Next())) != null)
                    if (a.GetClassName() == 'WolfStatic20')
                        keys++;
                Console.Printf("WOLFDBG bosskill aftermath: map=%s "
                               "goldkeys=%d", Level.MapName, keys);
            }
        }

        // co-op sight probe: warp PLAYER 1 next to a dormant mutant with
        // the host far away; the mutant must wake and target player 1
        // without any damage (user repro: blind-to-joiner enemies)
        CVar csv = CVar.FindCVar("wolf_dbg_coopsight");
        if (csv != null && csv.GetInt() != 0 && playeringame[1]
            && players[1].mo != null)
        {
            if (t == 60)
            {
                ThinkerIterator mit = ThinkerIterator.Create("WolfEnemySim");
                WolfEnemySim m;
                while ((m = WolfEnemySim(mit.Next())) != null)
                {
                    if (m is "WolfMutant" && !m.attackMode)
                    {
                        int fx, fy;
                        [fx, fy] = m.DirDelta8(m.dir < 0 ? 0 : m.dir);
                        double wx = (m.tileX + fx) * 64 + 32;
                        double wy = 4096.0 - ((m.tileY + fy) * 64 + 32);
                        players[1].mo.SetOrigin((wx, wy, 0), false);
                        Console.Printf("WOLFDBG coopsight: joiner beside "
                                       "mutant at %d,%d", m.tileX, m.tileY);
                        break;
                    }
                }
            }
            if (t == 130)
            {
                ThinkerIterator mit = ThinkerIterator.Create("WolfEnemySim");
                WolfEnemySim m;
                while ((m = WolfEnemySim(mit.Next())) != null)
                {
                    if (m is "WolfMutant"
                        && m.Distance2D(players[1].mo) < 200)
                    {
                        Console.Printf("WOLFDBG coopsight result: awake=%d "
                                       "target=%d", m.attackMode,
                                       m.targetPlayer);
                        break;
                    }
                }
            }
        }

        // Spear boss probe: alert the boss, report its class, hp and
        // ASSIGNED sighting speed, then kill it and watch the outcome
        CVar sbv = CVar.FindCVar("wolf_dbg_sodboss");
        if (sbv != null && sbv.GetInt() != 0)
        {
            if (t == 40)
            {
                ThinkerIterator it = ThinkerIterator.Create("WolfEnemySim");
                WolfEnemySim e;
                while ((e = WolfEnemySim(it.Next())) != null)
                {
                    String cn = String.Format("%s", e.GetClassName());
                    if (cn.IndexOf("WolfTrans") == 0 || cn.IndexOf("WolfWill") == 0
                        || cn.IndexOf("WolfUber") == 0
                        || cn.IndexOf("WolfDeathKnight") == 0
                        || cn.IndexOf("WolfAngel") == 0)
                    {
                        e.FirstSighting();
                        Console.Printf("WOLFDBG sodboss: %s hp=%d speed=%d "
                                       "state=%d", cn, e.hitpoints,
                                       e.wolfSpeed, e.stateIdx);
                        break;
                    }
                }
            }
            if (t == 90)
            {
                ThinkerIterator it = ThinkerIterator.Create("WolfEnemySim");
                WolfEnemySim e;
                while ((e = WolfEnemySim(it.Next())) != null)
                {
                    String cn = String.Format("%s", e.GetClassName());
                    if (cn.IndexOf("WolfAngel") == 0 || cn.IndexOf("WolfTrans") == 0
                        || cn.IndexOf("WolfWill") == 0 || cn.IndexOf("WolfUber") == 0
                        || cn.IndexOf("WolfDeathKnight") == 0)
                    {
                        Console.Printf("WOLFDBG sodboss chasing: %s state=%d",
                                       cn, e.stateIdx);
                        e.KillActor_(players[0].mo);
                        break;
                    }
                }
            }
            if (t == 200)
            {
                int keys = 0;
                ThinkerIterator kit = ThinkerIterator.Create("Actor");
                Actor a;
                while ((a = Actor(kit.Next())) != null)
                    if (a.GetClassName() == 'SodStatic20')
                        keys++;
                Console.Printf("WOLFDBG sodboss aftermath: map=%s goldkeys=%d",
                               Level.MapName, keys);
            }
        }

        // lobby signage probe: how many labels spawned, and where
        CVar sgv = CVar.FindCVar("wolf_dbg_signs");
        if (sgv != null && sgv.GetInt() != 0 && t == 20)
        {
            ThinkerIterator it = ThinkerIterator.Create("WolfLobbySign");
            Actor a;
            int n = 0;
            String first = "";
            while ((a = Actor(it.Next())) != null)
            {
                if (n == 0)
                    first = String.Format("(%d,%d,%d) frame=%d",
                                          int(a.pos.x), int(a.pos.y),
                                          int(a.pos.z), a.frame);
                n++;
            }
            Console.Printf("WOLFDBG signs: n=%d first=%s spear=%d",
                           n, first, WolfDraw.IsSpear());
            Console.Printf("WOLFDBG menucolors: border=%02x bkgd=%02x "
                           "bord2=%02x deactive=%02x",
                           WolfDraw.C_BORDER_(), WolfDraw.C_BKGD_(),
                           WolfDraw.C_BORD2_(), WolfDraw.C_DEACTIVE_());
            // face the west aisle so a screenshot actually shows them
            if (players[0].mo != null)
                players[0].mo.Angle = 180;
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
