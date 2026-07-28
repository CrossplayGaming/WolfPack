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
                Console.Printf("Starting %s - %s",
                               EPNAMES[ep], SKNAMES[sk]);
                mo.A_StartSound("menu/advance", CHAN_AUTO);
                Level.ChangeLevel(EPMAPS[ep], 0,
                                  CHANGELEVEL_NOINTERMISSION
                                  | CHANGELEVEL_RESETINVENTORY, sk);
                return;
            }
            if (!host)
                continue;
            if (zone <= Z_EP6)
            {
                ep = zone - Z_EP1;
                Console.Printf("Episode %d: %s", ep + 1, EPNAMES[ep]);
            }
            else
            {
                // any east alcove CYCLES the skill (4 skills can't map
                // onto 6 alcoves positionally - user repro: the south
                // bands did nothing and the choice "didn't take")
                sk = (sk + 1) % 4;
                Console.Printf("Skill: %s", SKNAMES[sk]);
            }
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

    // one-time engine-color sync: the scoreboard swatch follows the
    // uniform even when wolf_skin arrived by config or +set rather than
    // through the Player Setup menu (ui scope - userinfo set, same as
    // the engine's own player menu)
    ui bool colorSynced;

    override void UiTick()
    {
        if (colorSynced)
            return;
        colorSynced = true;
        CVar sv = CVar.GetCVar("wolf_skin", players[consoleplayer]);
        if (sv != null)
            WolfPlayerSetupMenu.SyncEngineColor(sv.GetInt());
    }

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
        String l1 = String.Format("Episode %d: %s", ep + 1, EPNAMES[ep]);
        String l2 = String.Format("Skill: %s", SKNAMES[sk]);
        String l3 = consoleplayer == 0
            ? "West aisle: pick episode. East aisle: change skill. "
              "Hans's room: begin."
            : "The host is choosing episode and skill.";
        WolfDraw.Text(sm, 160 - sm.StringWidth(l1) / 2, 3, l1,
                      WolfPal.Get(WolfMenu.C_READH));
        WolfDraw.Text(sm, 160 - sm.StringWidth(l2) / 2, 13, l2,
                      WolfPal.Get(WolfMenu.C_READH));
        WolfDraw.Text(sm, 160 - sm.StringWidth(l3) / 2, 23, l3,
                      WolfPal.Get(WolfMenu.C_READ));
    }
}
