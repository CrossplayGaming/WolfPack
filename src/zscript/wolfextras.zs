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
        // sv tri-states: 0 Default, 1 Off, 2 On (engine menudef). The
        // MAPINFO No* blocks are demonstrably inert in this engine, so
        // "classic" must FORCE-DENY (1), not obey the map (0).
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

// Multiplayer scaffold: the page exists and holds its place on the main
// menu; hosting/joining lands with the co-op/PvP phases.
class WolfMPMenu : WolfMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        labels.Clear(); itemStates.Clear();
        labels.Push("Host Co-op Game");   itemStates.Push(IT_DISABLED);
        labels.Push("Host Deathmatch");   itemStates.Push(IT_DISABLED);
        labels.Push("Join Game");         itemStates.Push(IT_DISABLED);
        labels.Push("Player Setup");      itemStates.Push(IT_DISABLED);
        labels.Push("Back");              itemStates.Push(IT_RETURN);
        sel = labels.Size() - 1;
    }

    override void Drawer()
    {
        DrawBackground();
        String t = "Multiplayer";
        WolfDraw.Text(big, 160 - big.StringWidth(t) / 2, 4, t,
                      WolfPal.Get(C_READH));
        DrawWindowBox(MENU_X - 8, MENU_Y - 3, MENU_W + 20,
                      13 * labels.Size() + 6);
        DrawItems(MENU_X, MENU_Y, 24, 13);
        String note = "To play online: run multiplayer.bat";
        WolfDraw.Text(big, 160 - big.StringWidth(note) / 2, 150, note,
                      WolfPal.Get(C_READ));
        DrawGun(MENU_X, MENU_Y, 13);
    }

    override void OnChoose(int index)
    {
        if (itemStates[index] == IT_RETURN)
            Close();
    }
}
