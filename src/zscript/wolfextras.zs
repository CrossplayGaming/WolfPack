// Cheats, Modernization, and the Multiplayer scaffold (user roadmap).
//
// Cheats (D-001): Doom-style set, all inert until used, in-game only.
// ui cannot touch play state, so actions cross via wolf_cheat net
// events handled in WolfGameState; god/noclip lamps read player.cheats.
//
// Modernization: sv_jump/sv_crouch/sv_freelook are the engine's
// tri-state MAPINFO overrides (0 obey the map = classic, 2 force-allow
// = modern). They archive, so the choice persists per player without
// fighting the config traps. Enabling freelook also flips the freelook
// input cvar on.

class WolfCheatMenu : WolfWidgetMenu
{
    enum ECheat { CH_GOD, CH_NOCLIP, CH_ARSENAL, CH_HEALTH, CH_SKIP };

    bool ingame;

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Cheats";
        ingame = Level.MapName != "TITLEMAP";
        int st = ingame ? IT_NORMAL : IT_DISABLED;
        AddRow(W_COMMAND, "God Mode", "", st);
        AddRow(W_COMMAND, "No Clipping", "", st);
        AddRow(W_COMMAND, "Full Arsenal", "", st);
        AddRow(W_COMMAND, "Full Health", "", st);
        AddRow(W_COMMAND, "Skip This Floor", "", st);
        AddToggle("Reveal Automap", "am_cheat");
        winH = 13 * labels.Size() + 6;
        sel = ingame ? 0 : labels.Size() - 1;
    }

    override void Drawer()
    {
        Super.Drawer();
        // live lamps for the toggling cheats
        if (ingame && players[consoleplayer].mo != null)
        {
            int ch = players[consoleplayer].cheats;
            WolfDraw.Pic(winX + 8, winY + CH_GOD * 13 + 2,
                         (ch & CF_GODMODE) ? "C_SEL" : "C_NOTSEL");
            WolfDraw.Pic(winX + 8, winY + CH_NOCLIP * 13 + 2,
                         (ch & CF_NOCLIP) ? "C_SEL" : "C_NOTSEL");
        }
    }

    override void OnChoose(int index)
    {
        if (!ingame || index > CH_SKIP)
            return;
        EventHandler.SendNetworkEvent("wolf_cheat", index);
        if (index == CH_SKIP)
            BackOut();
    }
}

// ---------------------------------------------------------------------------

class WolfModernMenu : WolfWidgetMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Modernization";
        // sv tri-states, SETTLED by the IsJumpingAllowed() probe:
        // 0=allowed (the map No* blocks are inert), 1=DENIED, 2=ALLOWED.
        // Earlier contrary observations were the companion-cvar deferral
        // bug confounding the tests. Classic force-denies: OFF = 1.
        AddToggleV("Mouse Vertical Aim", "sv_freelook", 2, 1);
        AddToggleV("Jumping", "sv_jump", 2, 1);
        AddBindRow("  Jump Key", "+jump");
        AddToggleV("Crouching", "sv_crouch", 2, 1);
        AddBindRow("  Crouch Key", "+crouch");
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }

    override void Drawer()
    {
        // bind rows grey out while their feature is off
        CVar j = CVar.GetCVar("sv_jump", players[consoleplayer]);
        CVar c = CVar.GetCVar("sv_crouch", players[consoleplayer]);
        itemStates[2] = (j != null && j.GetInt() == 2) ? IT_NORMAL
                                                       : IT_DISABLED;
        itemStates[4] = (c != null && c.GetInt() == 2) ? IT_NORMAL
                                                       : IT_DISABLED;
        Super.Drawer();
    }

    override void OnToggled(int i, int newValue)
    {
        // freelook also needs the INPUT cvar. Computed from the value we
        // just SET - server cvars apply deferred, so re-reading here
        // returns the OLD value (that inverted this toggle once).
        if (wCVar[i] == "sv_freelook")
        {
            CVar fl = CVar.GetCVar("freelook", players[consoleplayer]);
            if (fl != null)
                fl.SetInt(newValue == 2 ? 1 : 0);
        }
    }
}

// ---------------------------------------------------------------------------

// Player Setup: pick the uniform recolor other players see in netgames.
// wolf_skin is userinfo (per-player, replicated, archived); WolfPlayer
// remaps its BJ1 sprites to the chosen variant at Tick time.
class WolfPlayerSetupMenu : WolfWidgetMenu
{
    const PREVIEW_H = 100;

    // engine `color` userinfo per uniform: drives the scoreboard's
    // player swatch so it matches the clothing recolor
    static const String SKINCOLORS[] = { "9c 9c 9c", "24 24 d8",
                                         "d8 24 24", "d8 a0 60" };

    static void SyncEngineColor(int v)
    {
        CVar c = CVar.GetCVar("color", players[consoleplayer]);
        if (c != null)
            c.SetString(SKINCOLORS[clamp(v, 0, 3)]);
    }

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Player Setup";
        AddMulti("Uniform", "wolf_skin", "Grey,Blue,Red,Tan");
        winH = 13 * labels.Size() + 6 + PREVIEW_H;
        sel = 0;
    }

    override void Adjust(int i, int dir)
    {
        // cvar sets apply deferred - compute the post-cycle value from
        // the PRE-set reading (the freelook-companion lesson)
        CVar sv = GetCV(0);
        int before = sv == null ? 0 : sv.GetInt();
        Super.Adjust(i, dir);
        if (i == 0 && sv != null)
            SyncEngineColor((before + dir + 4) % 4);
    }

    override void Drawer()
    {
        Super.Drawer();
        // live preview: the standing frame in the chosen color, facing
        // the viewer, drawn inside the window below the row
        CVar cv = GetCV(0);
        int v = cv == null ? 0 : clamp(cv.GetInt(), 0, 3);
        String lump = String.Format("BJ%dSA1", v + 1);
        TextureID t = TexMan.CheckForTexture(lump, TexMan.Type_Sprite);
        if (!t.IsValid())
            return;
        double sx = WolfDraw.ScaleX(), sy = WolfDraw.ScaleY();
        // 64x64 art shown at 1.4x; sprite grab offsets zeroed so (x,y)
        // is the top-left corner like every other menu draw
        double side = 64 * 1.4;
        double px = winX + (winW - side) / 2;
        double py = winY + 13 * labels.Size() + 8;
        screen.DrawTexture(t, true, WolfDraw.OrgX() + px * sx, py * sy,
                           DTA_DestWidthF, side * sx,
                           DTA_DestHeightF, side * sy,
                           DTA_LeftOffsetF, 0.0, DTA_TopOffsetF, 0.0);
    }
}

// ---------------------------------------------------------------------------

// Multiplayer scaffold: the page exists and holds its place on the main
// menu; hosting/joining lands with the co-op/PvP phases.
class WolfMPMenu : WolfMenu
{
    // deathmatch rules, carried in the relaunch marker so the launcher
    // never has to ask in a terminal
    static const int FRAGV[] = { 5, 10, 20, 0 };
    static const int TIMEV[] = { 0, 5, 10, 15 };
    int fragIdx;
    int timeIdx;

    String FragLabel()
    {
        return FRAGV[fragIdx] == 0 ? "  DM Frag Limit: None"
            : String.Format("  DM Frag Limit: %d", FRAGV[fragIdx]);
    }

    String TimeLabel()
    {
        return TIMEV[timeIdx] == 0 ? "  DM Time Limit: None"
            : String.Format("  DM Time Limit: %d min", TIMEV[timeIdx]);
    }

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        fragIdx = 1;                             // first to 10
        timeIdx = 0;
        labels.Clear(); itemStates.Clear();
        labels.Push("Host Co-op: 2 Players");    itemStates.Push(IT_NORMAL);
        labels.Push("Host Co-op: 3 Players");    itemStates.Push(IT_NORMAL);
        labels.Push("Host Co-op: 4 Players");    itemStates.Push(IT_NORMAL);
        labels.Push("Host Deathmatch: 2");       itemStates.Push(IT_NORMAL);
        labels.Push("Host Deathmatch: 4");       itemStates.Push(IT_NORMAL);
        labels.Push(FragLabel());                itemStates.Push(IT_NORMAL);
        labels.Push(TimeLabel());                itemStates.Push(IT_NORMAL);
        labels.Push("Join (code on clipboard)"); itemStates.Push(IT_NORMAL);
        labels.Push("Player Setup");             itemStates.Push(IT_NORMAL);
        labels.Push("Back");                     itemStates.Push(IT_RETURN);
        sel = 0;
    }

    override void Drawer()
    {
        DrawBackground();
        String t = "Multiplayer";
        WolfDraw.Text(big, 160 - big.StringWidth(t) / 2, 4, t,
                      WolfPal.Get(C_READH));
        DrawWindowBox(MENU_X - 24, MENU_Y - 3, MENU_W + 60,
                      13 * labels.Size() + 6);
        DrawItems(MENU_X - 16, MENU_Y, 24, 13);
        String note = "The game restarts to start or join a session";
        WolfDraw.Text(big, 160 - big.StringWidth(note) / 2, 172, note,
                      WolfPal.Get(C_READ));
        DrawGun(MENU_X - 16, MENU_Y, 13);
    }

    // menu -> wrapper: the request rides an archived cvar (ZScript has
    // no file IO); the quit confirm - our own messagebox - notices it
    // and asks about restarting instead of quitting
    const KEY_F15 = 0x66;

    void Request(String what)
    {
        // Bindings apply INSTANTLY from ui and archive at exit - unlike
        // cvar sets (server and user both), which defer to game tics
        // that never come while the menu has the game paused. F15: no
        // physical keyboard in circulation has one.
        Bindings.SetBind(KEY_F15, "wolf_mp_marker " .. what);
        Menu.SetMenu("QuitMenu");
    }

    String DMRules()
    {
        return String.Format("f%d t%d", FRAGV[fragIdx], TIMEV[timeIdx]);
    }

    override void OnChoose(int index)
    {
        switch (index)
        {
        case 0: Request("host 2");    break;
        case 1: Request("host 3");    break;
        case 2: Request("host 4");    break;
        case 3: Request("hostdm 2 " .. DMRules());  break;
        case 4: Request("hostdm 4 " .. DMRules());  break;
        case 5:
            fragIdx = (fragIdx + 1) % 4;
            labels[5] = FragLabel();
            MenuSound("menu/change");
            break;
        case 6:
            timeIdx = (timeIdx + 1) % 4;
            labels[6] = TimeLabel();
            MenuSound("menu/change");
            break;
        case 7: Request("join");      break;
        case 8: Menu.SetMenu("WolfPlayerSetupMenu"); break;
        case 9: Close();              break;
        }
    }
}
