// Multiplayer lobby flow (LOBBY map, generated from Hans's level).
//
// The pillared hall is the control surface: the west aisle's six bands
// (between the pillar-stub rows) select the episode, the east aisle's
// top four bands select the skill, and walking into Hans's chamber
// COMMITS - ChangeLevel to the episode start at the chosen skill, all
// nodes following in lockstep. Selection is walk-over and re-triggers
// harmlessly; only the commit needs deliberate travel through a door.
//
// Host-only: player 0 (the -host node) owns selection and launch.
// Everyone sees the same overlay and messages - this runs in play
// scope, deterministically on every node.

// A floating label over a selectable alcove. The art is generated at
// build time from the Wolf font (make_assets): frames A-K are the grey
// unselected labels, L-V the gold selected ones, so highlighting is a
// frame swap. Real world sprites, so perspective/occlusion are the
// engine's problem, not ours.
class WolfLobbySign : Actor
{
    int labelIdx;               // 0-10, indexes the generated frames

    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +NOINTERACTION
        +BRIGHT
        Scale 1.4;              // legible from the centre aisle
    }

    void SetLabel(int idx, bool selected)
    {
        labelIdx = idx;
        frame = idx + (selected ? 11 : 0);
    }

    States
    {
    Spawn:
        LOBS A -1;
        Stop;
    // registration for every generated frame (playbook 4)
    Reg:
        LOBS ABCDEFGHIJKLMNOPQRSTUV -1;
        Stop;
    }
}

class WolfLobby : EventHandler
{
    // pending choice (play state, lockstep-identical everywhere)
    int ep;
    int sk;
    bool launched;
    int lastZone[MAXPLAYERS];

    enum EZone
    {
        Z_NONE = 0,
        Z_EP1, Z_EP2, Z_EP3, Z_EP4, Z_EP5, Z_EP6,
        Z_SK1, Z_SK2, Z_SK3, Z_SK4, Z_SK5, Z_SK6,
        Z_START,
    };

    static const String EPMAPS[] = { "MAP01", "MAP11", "MAP21",
                                     "MAP31", "MAP41", "MAP51" };
    static const String EPNAMES[] = {
        "Escape from Wolfenstein", "Operation: Eisenfaust",
        "Die, Fuhrer, Die!", "A Dark Secret",
        "Trail of the Madman", "Confrontation" };
    static const String SKNAMES[] = {
        "Can I play, Daddy?", "Don't hurt me.",
        "Bring 'em on!", "I am Death incarnate!" };

    clearscope bool Active()
    {
        return Level.MapName ~== "LOBBY";
    }

    override void WorldLoaded(WorldEvent e)
    {
        if (deathmatch)
            SanitizeArena();
        if (!Active())
            return;
        ep = 0;
        sk = 2;                     // Wolf menu default: Bring 'em on!
        launched = false;
        for (int p = 0; p < MAXPLAYERS; p++)
            lastZone[p] = Z_NONE;
        PlaceSigns();
    }

    // Deathmatch arena pass, any map: the campaign furniture that has no
    // business refereeing a PvP match goes. Enemies die here rather than
    // via -nomonsters because the Wolf sim actors are custom and never
    // carried the engine's monster flag (user repro: Hans in the arena).
    // Locked doors open freely - the gold key only exists as Hans's drop,
    // so his door would otherwise stay locked forever - and the victory
    // tiles go so nobody ends the match by walking the top corridor.
    void SanitizeArena()
    {
        int ne, nv;
        ThinkerIterator eit = ThinkerIterator.Create("WolfEnemySim");
        Actor a;
        while ((a = Actor(eit.Next())) != null)
        {
            a.Destroy();
            ne++;
        }
        // doors self-unlock in WolfDoor.PostBeginPlay (which runs on the
        // first tick, AFTER this) - writing lock here got overwritten
        ThinkerIterator vit = ThinkerIterator.Create("WolfVictoryTrigger");
        while ((a = Actor(vit.Next())) != null)
        {
            a.Destroy();
            nv++;
        }
        CVar cv = CVar.FindCVar("wolf_dbg_check");
        if (cv != null && cv.GetInt() != 0)
            Console.Printf("WOLFDBG arena: enemies=%d victory=%d", ne, nv);
        // the curated drops are placed by WL6-hall tile coordinates, so
        // they only make sense on that arena; Spear's DM floors keep
        // their own map items (sv_itemrespawn regenerates them)
        if (Level.MapName ~== "MAP09" && !WolfDraw.IsSpear())
            PlaceArenaPickups();
    }

    // deathmatch conventions for the 1v1 arena: a contested chaingun in
    // the hall center, a machine gun near each spawn's approach, health
    // in the side aisles, clips in the hall corners. sv_itemrespawn
    // (set at DM launch) regenerates them; corpse drops never respawn.
    void PlaceArenaPickups()
    {
        static const int ITEMS[] = {
            34, 33, 0,      // chaingun - hall center
            34, 48, 1,      // machine gun - start-room approach
            34, 17, 1,      // machine gun - chamber anteroom
            27, 34, 2,      // first aid - west aisle
            41, 34, 2,      // first aid - east aisle
            27, 22, 3, 41, 22, 3,   // clips - hall corners
            27, 42, 3, 41, 42, 3
        };
        static const String CLS[] = { "WolfStatic28", "WolfStatic27",
                                      "WolfStatic25", "WolfStatic26" };
        for (int i = 0; i < 24; i += 3)
        {
            double wx = ITEMS[i] * 64 + 32;
            double wy = 4096.0 - (ITEMS[i + 1] * 64 + 32);
            Actor.Spawn(CLS[ITEMS[i + 2]], (wx, wy, 0));
        }
    }

    // ---- signage ----------------------------------------------------
    // One floating label per selectable alcove, at its centre tile. The
    // episode aisle is skipped under Spear (one campaign), and skills
    // occupy the first four east bands - the last two carry no label
    // and no zone, which is now self-evident rather than a dead spot.
    Array<WolfLobbySign> signs;
    Array<int> signKind;        // 0 = episode, 1 = skill, 2 = start

    void PlaceSigns()
    {
        signs.Clear();
        signKind.Clear();
        bool spear = WolfDraw.IsSpear();
        for (int band = 0; band < 6; band++)
        {
            int ty = 22 + band * 4;             // centre row of the band
            if (!spear)
                AddSign(27, ty, band, 0);       // west: episodes 1-6
            if (band < 4)
                AddSign(41, ty, 6 + band, 1);   // east: the four skills
        }
        AddSign(34, 12, 10, 2);                 // the commit room
        RefreshSigns();
    }

    void AddSign(int tx, int ty, int labelIdx, int kind)
    {
        double wx = tx * 64 + 32;
        double wy = 4096.0 - (ty * 64 + 32);
        Actor a = Actor.Spawn("WolfLobbySign", (wx, wy, 40));
        WolfLobbySign sg = WolfLobbySign(a);
        if (sg == null)
            return;
        sg.SetLabel(labelIdx, false);
        signs.Push(sg);
        signKind.Push(kind);
    }

    // gold on the current picks, grey elsewhere
    void RefreshSigns()
    {
        for (int i = 0; i < signs.Size(); i++)
        {
            WolfLobbySign sg = signs[i];
            if (sg == null)
                continue;
            int k = signKind[i];
            bool on = (k == 0 && sg.labelIdx == ep)
                   || (k == 1 && sg.labelIdx - 6 == sk)
                   || k == 2;
            sg.SetLabel(sg.labelIdx, on);
        }
    }

    // hall geometry (tile coords of the source map, see the layout read
    // in convert_udmf.py): pillar-stub rows 24/28/32/36/40 divide both
    // side aisles into six bands y 21-23, 25-27, 29-31, 33-35, 37-39,
    // 41-43. West aisle x 26-28, east aisle x 40-42; the spawn cluster
    // sits in the neutral center aisle. Hans's chamber: y 10-14.
    int ZoneAt(int tx, int ty)
    {
        if (ty >= 10 && ty <= 14 && tx >= 31 && tx <= 37)
            return Z_START;
        int band = -1;
        if (ty >= 21 && ty <= 43 && ty % 4 != 0)
            band = (ty - 21) / 4;
        if (band < 0)
            return Z_NONE;
        if (tx >= 26 && tx <= 28)
            return Z_EP1 + band;
        if (tx >= 40 && tx <= 42)
            return Z_SK1 + band;
        return Z_NONE;
    }

    override void WorldTick()
    {
        if (!Active() || launched)
            return;
        for (int p = 0; p < MAXPLAYERS; p++)
        {
            if (!playeringame[p] || players[p].mo == null)
                continue;
            PlayerPawn mo = players[p].mo;
            int zone = ZoneAt(int(mo.pos.x) >> 6,
                              63 - (int(mo.pos.y) >> 6));
            if (zone == lastZone[p])
                continue;
            lastZone[p] = zone;
            if (zone == Z_NONE)
                continue;
            bool host = (p == 0);
            if (zone == Z_START)
            {
                if (!host)
                {
                    Console.Printf("Only the host can start the game.");
                    continue;
                }
                launched = true;
                // Spear is one linear campaign: always floor one
                String dest = WolfDraw.IsSpear() ? "MAP01" : EPMAPS[ep];
                if (WolfDraw.IsSpear())
                    Console.Printf("Starting Spear of Destiny - %s",
                                   SKNAMES[sk]);
                else
                    Console.Printf("Starting %s - %s",
                                   EPNAMES[ep], SKNAMES[sk]);
                mo.A_StartSound("menu/advance", CHAN_AUTO);
                Level.ChangeLevel(dest, 0,
                                  CHANGELEVEL_NOINTERMISSION
                                  | CHANGELEVEL_RESETINVENTORY, sk);
                return;
            }
            if (!host)
                continue;
            if (zone <= Z_EP6 && !WolfDraw.IsSpear())
            {
                ep = zone - Z_EP1;
                Console.Printf("Episode %d: %s", ep + 1, EPNAMES[ep]);
            }
            else
            {
                // positional again: the first four east bands carry the
                // four skill signs, so there is no longer a hidden
                // mapping to guess (the cycling was a workaround for
                // unlabelled alcoves)
                int band = zone - Z_SK1;
                if (band > 3)
                    continue;                   // unlabelled, no zone
                sk = band;
                Console.Printf("Skill: %s", SKNAMES[sk]);
            }
            RefreshSigns();
            mo.A_StartSound("menu/change", CHAN_AUTO);
        }
    }

    // ---- Wolf-styled kill feed --------------------------------------
    // The engine draws notify lines (obituaries included) in the console
    // font, hardwired - SmallFont replacement can't reach it. Engine
    // obituaries are suppressed (show_obituaries 0 in DEFCVARS + launch
    // args) and netgame deaths render here in the Wolf font instead.
    // Queue is play state (deterministic on every node); drawing is ui.
    const FEED_TICS = 140;              // 4 s on screen
    Array<String> feed;
    Array<int> feedBorn;

    override void WorldThingDied(WorldEvent e)
    {
        if (!netgame || e.Thing == null || e.Thing.player == null)
            return;
        String victim = e.Thing.player.GetUserName();
        String msg;
        Actor killer = e.Thing.player.attacker;
        if (killer != null && killer.player != null
            && killer != e.Thing)
            msg = String.Format("%s was gunned down by %s", victim,
                                killer.player.GetUserName());
        else
            msg = String.Format("%s died", victim);
        feed.Push(msg);
        feedBorn.Push(Level.maptime);
        if (feed.Size() > 4)
        {
            feed.Delete(0);
            feedBorn.Delete(0);
        }
    }

    // persistent status readout, drawn Wolf-style at the top of the view.
    // Small font: the big one overflows virtual 320 and clips both edges
    // (user screenshot).
    override void RenderOverlay(RenderEvent e)
    {
        Font kf = Font.GetFont("wolfprop");
        if (kf != null)
        {
            int y = 2;
            for (int i = 0; i < feed.Size(); i++)
            {
                if (Level.maptime - feedBorn[i] > FEED_TICS)
                    continue;
                WolfDraw.Text(kf, 2, y, feed[i],
                              WolfPal.Get(WolfMenu.C_READH));
                y += 11;
            }
        }
        if (!Active() || launched)
            return;
        Font sm = Font.GetFont("wolfprop");
        if (sm == null)
            return;
        String l1 = WolfDraw.IsSpear() ? "Spear of Destiny"
            : String.Format("Episode %d: %s", ep + 1, EPNAMES[ep]);
        String l2 = String.Format("Skill: %s", SKNAMES[sk]);
        int bl = Wads.CheckNumForFullName("BUILDID");
        if (bl >= 0)
            l2 = l2 .. "   Build: " .. Wads.ReadLump(bl);
        String l3 = consoleplayer == 0
            ? (WolfDraw.IsSpear()
               ? "Either aisle: change skill. The north room: begin."
               : "West aisle: pick episode. East aisle: change skill. "
                 "Hans's room: begin.")
            : "The host is choosing episode and skill.";
        WolfDraw.Text(sm, 160 - sm.StringWidth(l1) / 2, 3, l1,
                      WolfPal.Get(WolfMenu.C_READH));
        WolfDraw.Text(sm, 160 - sm.StringWidth(l2) / 2, 13, l2,
                      WolfPal.Get(WolfMenu.C_READH));
        WolfDraw.Text(sm, 160 - sm.StringWidth(l3) / 2, 23, l3,
                      WolfPal.Get(WolfMenu.C_READ));
    }
}
