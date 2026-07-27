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
                         (ch & CF_NOCLIP2) ? "C_SEL" : "C_NOTSEL");
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
        AddToggleV("Mouse Vertical Aim", "sv_freelook", 2);
        AddToggleV("Jumping", "sv_jump", 2);
        AddToggleV("Crouching", "sv_crouch", 2);
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }

    override void Adjust(int i, int dir)
    {
        Super.Adjust(i, dir);
        // freelook also needs the INPUT cvar; classic mode turns it off
        if (wCVar[i] == "sv_freelook")
        {
            CVar fl = CVar.GetCVar("freelook", players[consoleplayer]);
            CVar sv = GetCV(i);
            if (fl != null && sv != null)
                fl.SetInt(sv.GetInt() == 2 ? 1 : 0);
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
        String note = "Co-op and PvP arrive in a later update";
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
