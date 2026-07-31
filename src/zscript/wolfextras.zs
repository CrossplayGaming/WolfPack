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
        // wolf_mod_* are the archived source of truth (the sv
        // tri-states never archive, so a menu bound to them could not
        // track across launches - user repro). OnToggled pushes each
        // change into the sv gate; level load re-applies (lobby.zs).
        AddToggleV("Mouse Vertical Aim", "wolf_mod_freelook", 1, 0);
        AddToggleV("Jumping", "wolf_mod_jump", 1, 0);
        AddBindRow("  Jump Key", "+jump");
        AddToggleV("Crouching", "wolf_mod_crouch", 1, 0);
        AddBindRow("  Crouch Key", "+crouch");
        AddToggleV("Third-Person View", "wolf_mod_tp", 1, 0);
        // always-available swap key (user decision: unlike jump/crouch
        // there is no availability gate - bind it once, flip views any
        // time). `toggle` on the replicated user cvar is the whole
        // mechanism; chasecam.zs reacts on the next tick.
        AddBindRow("  3rd-Person Key", "toggle wolf_mod_tp");
        AddToggleV("Floor + Ceiling Textures", "wolf_mod_flats", 1, 0);
        AddCommand("Crosshair Setup");
        AddCommand("Lighting Setup");
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }

    override void OnChoose(int index)
    {
        if (labels[index] == "Crosshair Setup")
            Menu.SetMenu("WolfCrosshairMenu");
        else if (labels[index] == "Lighting Setup")
            Menu.SetMenu("WolfLightMenu");
    }

    override void Drawer()
    {
        // bind rows grey out while their feature is off
        CVar j = CVar.GetCVar("wolf_mod_jump", players[consoleplayer]);
        CVar c = CVar.GetCVar("wolf_mod_crouch", players[consoleplayer]);
        itemStates[2] = (j != null && j.GetInt() != 0) ? IT_NORMAL
                                                       : IT_DISABLED;
        itemStates[4] = (c != null && c.GetInt() != 0) ? IT_NORMAL
                                                       : IT_DISABLED;
        Super.Drawer();
    }

    override void OnToggled(int i, int newValue)
    {
        // push the change into the engine gate immediately (menu scope
        // may set server cvars). Computed from the value we just SET -
        // cvar sets apply deferred, re-reading returns the OLD value.
        String sv = wCVar[i] == "wolf_mod_jump" ? "sv_jump"
                  : wCVar[i] == "wolf_mod_crouch" ? "sv_crouch"
                  : wCVar[i] == "wolf_mod_freelook" ? "sv_freelook" : "";
        if (sv.Length() > 0)
        {
            CVar g = CVar.FindCVar(sv);
            if (g != null)
                g.SetInt(newValue != 0 ? 2 : 1);
        }
        if (wCVar[i] == "wolf_mod_freelook")
        {
            CVar fl = CVar.GetCVar("freelook", players[consoleplayer]);
            if (fl != null)
                fl.SetInt(newValue != 0 ? 1 : 0);
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
            // static methods need the class-qualified name for
            // static const arrays
            c.SetString(WolfPlayerSetupMenu.SKINCOLORS[clamp(v, 0, 3)]);
    }

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Player Setup";
        AddMulti("Uniform", "wolf_skin", "Grey,Blue,Red,Tan");
        CVar sv0 = GetCV(0);
        if (sv0 != null)
            SyncEngineColor(sv0.GetInt());
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
        // entering the MP menu syncs the scoreboard swatch to the
        // uniform (userinfo writes are menu-code-only)
        CVar skv = CVar.GetCVar("wolf_skin", players[consoleplayer]);
        if (skv != null)
            WolfPlayerSetupMenu.SyncEngineColor(skv.GetInt());
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
        labels.Push("Join a Game");             itemStates.Push(IT_NORMAL);
        labels.Push("Player Setup");             itemStates.Push(IT_NORMAL);
        labels.Push("Back");                     itemStates.Push(IT_RETURN);
        sel = 0;
    }

    // ten rows outgrow the standard MENU_Y start: from 55 the box ran
    // to y 188, colliding with the note at 172 (user repro). Start
    // higher; box bottom lands at 163.
    const MP_TOP = 30;

    override void Drawer()
    {
        DrawBackground();
        String t = "Multiplayer";
        WolfDraw.Text(big, 160 - big.StringWidth(t) / 2, 4, t,
                      WolfPal.Get(C_READH));
        DrawWindowBox(MENU_X - 24, MP_TOP - 3, MENU_W + 60,
                      13 * labels.Size() + 6);
        DrawItems(MENU_X - 16, MP_TOP, 24, 13);
        // small font: both lines measure 374 wolfbig units - wider than
        // the 320 screen (the lobby-overlay lesson, again)
        Font sm = Font.GetFont("wolfprop");
        String note = "The game restarts to start or join a session";
        String note2 = "Join reads the invite code from your clipboard";
        if (sm != null)
        {
            WolfDraw.Text(sm, 160 - sm.StringWidth(note) / 2, 168, note,
                          WolfPal.Get(C_READ));
            WolfDraw.Text(sm, 160 - sm.StringWidth(note2) / 2, 179, note2,
                          WolfPal.Get(C_READ));
        }
        DrawGun(MENU_X - 16, MP_TOP, 13);
    }

    // menu -> wrapper: the request rides an archived cvar (ZScript has
    // no file IO); the quit confirm - our own messagebox - notices it
    // and asks about restarting instead of quitting
    const KEY_F15 = 0x66;

    // which game is this build? mapinfo_sod.txt ships only in
    // spear.ipk3, so its presence is the tell
    void Request(String what)
    {
        if (WolfDraw.IsSpear())
            what = what .. " spear";
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


// ---------------------------------------------------------------------------

// Crosshair setup, Wolf-styled (Eric: "easy size, color and style").
// Fronts the engine's own crosshair cvars so archiving/replication is
// the engine's problem; the only invention is the color row, which
// cycles named presets into the crosshaircolor color-cvar (a raw color
// string is not a menu-friendly thing to adjust).
class WolfCrosshairMenu : WolfWidgetMenu
{
    static const String colorNames[] = { "White", "Gold", "Green",
                                         "Red", "Blue", "Grey" };
    static const String colorVals[] = { "ff ff ff", "ff f7 00",
                                        "00 ff 00", "ff 00 00",
                                        "40 80 ff", "c0 c0 c0" };

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Crosshair";
        AddToggle("Crosshair", "crosshairon");
        AddMulti("Style", "crosshair",
                 "Default,Cross 1,Cross 2,X,Circle,Angle,Triangle,Dot");
        AddSlider("Size", "crosshairscale", 0.25, 2.0, 0.25);
        AddMulti("Color", "wolf_xhair_color",
                 "White,Gold,Green,Red,Blue,Grey");
        AddToggle("Grow On Pickup", "crosshairgrow");
        AddMulti("Health Color", "crosshairhealth",
                 "Off,Standard,Enhanced");
        winH = 13 * labels.Size() + 6 + 30;      // room for the preview
        sel = 0;
        // adopt whatever color is archived so the row shows the truth
        CVar cc = CVar.FindCVar("crosshaircolor");
        CVar idx = CVar.GetCVar("wolf_xhair_color",
                                players[consoleplayer]);
        if (cc != null && idx != null)
        {
            String cur = cc.GetString();
            for (int i = 0; i < colorVals.Size(); i++)
                if (cur ~== colorVals[i])
                    idx.SetInt(i);
        }
    }

    override void Adjust(int i, int dir)
    {
        Super.Adjust(i, dir);
        if (wCVar[i] == "wolf_xhair_color")
        {
            CVar idx = CVar.GetCVar("wolf_xhair_color",
                                    players[consoleplayer]);
            CVar cc = CVar.FindCVar("crosshaircolor");
            if (idx != null && cc != null)
                cc.SetString(colorVals[
                    clamp(idx.GetInt(), 0, colorVals.Size() - 1)]);
        }
    }

    override void Drawer()
    {
        Super.Drawer();
        // live preview under the rows: the actual engine lump, at the
        // chosen size, in the chosen color (styles are alpha images -
        // FillColor is exactly how the renderer colors them too)
        CVar st = CVar.FindCVar("crosshair");
        int style = st == null ? 0 : clamp(st.GetInt(), 0, 7);
        if (style == 0)
            return;
        TextureID t = TexMan.CheckForTexture(
            String.Format("XHAIRS%d", style), TexMan.Type_MiscPatch);
        if (!t.IsValid())
            return;
        CVar sc = CVar.FindCVar("crosshairscale");
        double k = sc == null ? 1.0 : clamp(sc.GetFloat(), 0.25, 2.0);
        CVar idx = CVar.GetCVar("wolf_xhair_color",
                                players[consoleplayer]);
        int ci = idx == null ? 0 : clamp(idx.GetInt(), 0,
                                         colorVals.Size() - 1);
        Color col = WolfCrosshairMenu.PresetColor(ci);
        int tw, th;
        [tw, th] = TexMan.GetSize(t);
        double sx = WolfDraw.ScaleX(), sy = WolfDraw.ScaleY();
        double px = 160, py = winY + 13 * labels.Size() + 16;
        screen.DrawTexture(t, true,
            WolfDraw.OrgX() + (px - tw * k) * sx,
            (py - th * k) * sy,
            DTA_DestWidthF, tw * k * 2 * sx,
            DTA_DestHeightF, th * k * 2 * sy,
            DTA_FillColor, col & 0xFFFFFF,
            DTA_AlphaChannel, true);    // alpha-only lump: without this
                                        // the preview is a filled square
    }

    static Color PresetColor(int i)
    {
        switch (i)
        {
        case 1:  return Color(255, 247, 0);
        case 2:  return Color(0, 255, 0);
        case 3:  return Color(255, 0, 0);
        case 4:  return Color(64, 128, 255);
        case 5:  return Color(192, 192, 192);
        }
        return Color(255, 255, 255);
    }
}


// ---------------------------------------------------------------------------

// Enhanced lighting page. The master toggle drives the world half
// (lighting.zs: depth shading + painted-pool swap, host-controlled)
// and pushes the local render half (dynamic lights + Doom light mode)
// so one switch does the whole look; the rest are per-player taste.
class WolfLightMenu : WolfWidgetMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Lighting";
        AddToggleV("Enhanced Lighting", "wolf_mod_light", 1, 0);
        AddToggle("Light Shadows", "gl_light_shadowmap");
        AddMulti("Ambient Occlusion", "gl_ssao",
                 "Off,Low,Medium,High");
        AddToggle("Bloom", "gl_bloom");
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }

    override void OnToggled(int i, int newValue)
    {
        if (wCVar[i] == "wolf_mod_light")
        {
            // local render companion: Software falloff (this engine's
            // enum: 0 Classic / 1 Software / 2 Vanilla; Vanilla banded
            // to near-black in long corridors) when on, Classic off
            CVar lm = CVar.FindCVar("gl_lightmode");
            if (lm != null)
                lm.SetInt(newValue != 0 ? 1 : 0);
        }
    }
}
