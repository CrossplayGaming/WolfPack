// The Wolf menu stack (WL_MENU.C), ECWolf-structured per D-006.
//
// Geometry and colours are the original's: MENU_X 76 / MENU_Y 55, 13px
// item pitch, indent 24, window BKGDCOLOR 0x2d outlined DEACTIVE 0x2b
// (top/left) and BORD2COLOR 0x23 (bottom/right), items in TEXTCOLOR 0x17
// / HIGHLIGHT 0x13, the return item in READCOLOR 0x4a / READHCOLOR 0x47,
// disabled items DEACTIVE. The gun cursor alternates C_CURSOR1/2 every 8
// Wolf tics. Text is the game's own font chunk 2 (extracted height 13 â€”
// matching the 13px pitch is a free cross-check).
//
// Structure is ECWolf's (user decision): New Game / Options / Load /
// Save / Read This! / End Game / Back to / Quit, with Options gathering
// the engine pages. Unlike Doom, the menu REPLACES the attract screens
// entirely â€” it paints the whole display and switches to MENUSONG
// (WONDERIN), and backing out returns to the title page of the attract
// loop, per the original's US_ControlPanel flow.

class WolfMenu : ListMenu
{
    const MENU_X = 76;
    const MENU_Y = 55;
    const MENU_W = 178;
    const MENU_H = 13 * 10 + 6;

    const C_TEXT     = 0x17;
    const C_HILITE   = 0x13;
    const C_READ     = 0x4a;
    const C_READH    = 0x47;
    const C_DEACTIVE = 0x2b;
    const C_BKGD     = 0x2d;
    const C_BORD2    = 0x23;
    const C_BORDER   = 0x29;
    const C_STRIPE   = 0x2c;

    // item states, WL_MENU.C color_norml/color_hlite indices
    enum EState { IT_DISABLED, IT_NORMAL, IT_RETURN, IT_EPISODE };

    Array<String> labels;
    Array<int> itemStates;
    int sel;
    int cursorTics;
    bool cursorAlt;
    Font big;

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        DontDim = true;
        big = Font.GetFont("wolfbig");
        S_ChangeMusic("WONDERIN", 0, true);      // MENUSONG (WL_MENU.H:34)
    }

    // ---- shared drawing --------------------------------------------------

    // plain menu screen: ClearMScreen + the mouse bar. The stripe and
    // "Options" plaque belong ONLY to the main/options pages — the
    // episode and skill screens draw without them (DrawNewEpisode /
    // DrawNewGame), which is also what keeps their titles clear.
    void DrawBackground()
    {
        WolfDraw.WideBar(0, 200, C_BORDER);      // ClearMScreen
        WolfDraw.Pic(112, 184, "C_MLBACK");
    }

    void DrawBanner()
    {
        WolfDraw.WideBar(10, 24, 0);             // DrawStripes(10)
        WolfDraw.WideBar(32, 1, C_STRIPE);
        WolfDraw.Pic(84, 0, "C_OPTS");
    }

    // DrawWindow + DrawOutline (WL_MENU.C:3419-3434)
    void DrawWindowBox(int x, int y, int w, int h)
    {
        WolfDraw.Bar(x, y, w, h, C_BKGD);
        WolfDraw.Bar(x, y, w, 1, C_DEACTIVE);            // top
        WolfDraw.Bar(x, y, 1, h, C_DEACTIVE);            // left
        WolfDraw.Bar(x, y + h, w, 1, C_BORD2);           // bottom
        WolfDraw.Bar(x + w, y, 1, h + 1, C_BORD2);       // right
    }

    // last-drawn item geometry, for mouse picking (320x200 units)
    int hitX, hitY, hitPitch;

    void DrawItems(int x, int y, int indent, int pitch)
    {
        hitX = x; hitY = y; hitPitch = pitch;
        for (int i = 0; i < labels.Size(); i++)
        {
            int st = itemStates[i];
            int pal;
            if (st == IT_DISABLED)     pal = C_DEACTIVE;
            else if (i == sel)
                pal = st == IT_RETURN ? C_READH
                    : (st == IT_EPISODE ? 0x67 : C_HILITE);
            else
                pal = st == IT_RETURN ? C_READ
                    : (st == IT_EPISODE ? 0x6b : C_TEXT);
            // two-line labels (episodes) split on '\n'
            String label = labels[i];
            int nl = label.IndexOf("\n");
            if (nl < 0)
                WolfDraw.Text(big, x + indent, y + i * pitch, label,
                              WolfPal.Get(pal));
            else
            {
                WolfDraw.Text(big, x + indent, y + i * pitch,
                              label.Left(nl), WolfPal.Get(pal));
                WolfDraw.Text(big, x + indent, y + i * pitch + 13,
                              label.Mid(nl + 1), WolfPal.Get(pal));
            }
        }
    }

    void DrawGun(int x, int y, int pitch)
    {
        WolfDraw.Pic(x, y + sel * pitch - 2,
                     cursorAlt ? "C_CURS2" : "C_CURS1");
    }

    override void Ticker()
    {
        // cursor flash: 8 Wolf tics = 4 engine tics per phase
        if (++cursorTics >= 4)
        {
            cursorTics = 0;
            cursorAlt = !cursorAlt;
        }
    }

    // ---- input -----------------------------------------------------------

    virtual void OnChoose(int index) {}
    virtual void OnBack()
    {
        if (mParentMenu != null)
            Close();
        else
            BackOut();
    }

    // leaving the whole menu: back to the game or the attract loop
    void BackOut()
    {
        if (Level.MapName == "TITLEMAP")
        {
            Close();
            Menu.SetMenu("WolfAttractMenu");
        }
        else
        {
            S_ChangeMusic(Level.Music);
            Close();
        }
    }

    int Move(int dir)
    {
        int n = labels.Size();
        for (int tries = 0; tries < n; tries++)
        {
            sel = (sel + dir + n) % n;
            if (itemStates[sel] != IT_DISABLED)
                break;
        }
        MenuSound("menu/cursor");
        return sel;
    }

    override bool MenuEvent(int mkey, bool fromcontroller)
    {
        switch (mkey)
        {
        case MKEY_Up:    Move(-1); return true;
        case MKEY_Down:  Move(1);  return true;
        case MKEY_Enter:
            if (itemStates[sel] != IT_DISABLED)
            {
                MenuSound("menu/advance");
                OnChoose(sel);
            }
            return true;
        case MKEY_Back:
            MenuSound("menu/backup");
            OnBack();
            return true;
        }
        return Super.MenuEvent(mkey, fromcontroller);
    }

    // Wolf mouse handling: the gun cursor rides the list — hovering a
    // row selects it, click activates. No free-floating dead cursor.
    override bool MouseEvent(int type, int x, int y)
    {
        if (hitPitch <= 0 || labels.Size() == 0)
            return false;
        double ux = (x - WolfDraw.OrgX()) / WolfDraw.ScaleX();
        double uy = y / WolfDraw.ScaleY();
        int idx = int((uy - hitY + 2) / hitPitch);
        if (idx >= 0 && idx < labels.Size() && uy >= hitY - 2
            && itemStates[idx] != IT_DISABLED)
        {
            if (idx != sel)
            {
                sel = idx;
                MenuSound("menu/cursor");
            }
            if (type == MOUSE_Release)
                OnChoose(sel);
        }
        return true;
    }

    // static window in the Message() style (WL_MENU.C:3490): TEXTCOLOR
    // face, black bottom/right, HIGHLIGHT top/left
    static void DrawStaticWindow(int x, int y, int w, int h)
    {
        WolfDraw.Bar(x, y, w, h, 0x17);
        WolfDraw.Bar(x, y, w, 1, 0x13);
        WolfDraw.Bar(x, y, 1, h, 0x13);
        WolfDraw.Bar(x, y + h, w, 1, 0);
        WolfDraw.Bar(x + w, y, 1, h + 1, 0);
    }
}

// ---------------------------------------------------------------------------

class WolfMainMenu : WolfMenu
{
    // ECWolf order (D-006)
    enum EItem { MI_NEWGAME, MI_OPTIONS, MI_MULTI, MI_LOAD, MI_SAVE,
                 MI_READ, MI_ENDGAME, MI_BACKTO, MI_QUIT };

    bool ingame;

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        ingame = Level.MapName != "TITLEMAP";
        labels.Clear(); itemStates.Clear();
        labels.Push("New Game");     itemStates.Push(IT_NORMAL);
        labels.Push("Options");      itemStates.Push(IT_NORMAL);
        labels.Push("Multiplayer");  itemStates.Push(IT_NORMAL);
        labels.Push("Load Game");    itemStates.Push(IT_NORMAL);
        labels.Push("Save Game");    itemStates.Push(ingame ? IT_NORMAL
                                                        : IT_DISABLED);
        labels.Push("Read This!");   itemStates.Push(IT_NORMAL);
        labels.Push("End Game");     itemStates.Push(ingame ? IT_NORMAL
                                                        : IT_DISABLED);
        labels.Push(ingame ? "Back to Game" : "Back to Demo");
        itemStates.Push(IT_RETURN);
        labels.Push("Quit");         itemStates.Push(IT_NORMAL);
        sel = MI_NEWGAME;
    }

    override void Drawer()
    {
        DrawBackground();
        DrawBanner();
        DrawWindowBox(MENU_X - 8, MENU_Y - 3, MENU_W, MENU_H);
        DrawItems(MENU_X, MENU_Y, 24, 13);
        DrawGun(MENU_X, MENU_Y, 13);
    }

    override void OnChoose(int index)
    {
        switch (index)
        {
        case MI_NEWGAME: Menu.SetMenu("WolfEpisodeMenu"); break;
        case MI_OPTIONS: Menu.SetMenu("WolfOptionsMenu"); break;
        case MI_MULTI:   Menu.SetMenu("WolfMPMenu");      break;
        case MI_LOAD:    Menu.SetMenu("LoadGameMenu");    break;
        case MI_SAVE:    Menu.SetMenu("SaveGameMenu");    break;
        case MI_READ:    Menu.SetMenu("WolfReadMenu");    break;
        case MI_ENDGAME: Menu.SetMenu("EndGameMenu");     break;
        case MI_BACKTO:  BackOut();                       break;
        case MI_QUIT:    Menu.SetMenu("QuitMenu");        break;
        }
    }

    override void OnBack() { BackOut(); }
}

// ---------------------------------------------------------------------------

class WolfOptionsMenu : WolfMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        labels.Clear(); itemStates.Clear();
        labels.Push("Control Setup");   itemStates.Push(IT_NORMAL);
        labels.Push("Sound Options");   itemStates.Push(IT_NORMAL);
        labels.Push("Display Options"); itemStates.Push(IT_NORMAL);
        labels.Push("Automap Options"); itemStates.Push(IT_NORMAL);
        labels.Push("Modernization");   itemStates.Push(IT_NORMAL);
        labels.Push("Cheats");          itemStates.Push(IT_NORMAL);
    }

    override void Drawer()
    {
        DrawBackground();
        DrawBanner();
        DrawWindowBox(MENU_X - 8, MENU_Y - 3, MENU_W + 30,
                      13 * labels.Size() + 6);
        DrawItems(MENU_X, MENU_Y, 24, 13);
        DrawGun(MENU_X, MENU_Y, 13);
    }

    override void OnChoose(int index)
    {
        // engine pages for now: interiors are the next reskin pass
        switch (index)
        {
        case 0: Menu.SetMenu("WolfControlMenu"); break;
        case 1: Menu.SetMenu("WolfSoundMenu");   break;
        case 2: Menu.SetMenu("WolfDisplayMenu"); break;
        case 3: Menu.SetMenu("WolfAutomapMenu"); break;
        case 4: Menu.SetMenu("WolfModernMenu");  break;
        case 5: Menu.SetMenu("WolfCheatMenu");   break;
        }
    }
}

// ---------------------------------------------------------------------------

class WolfEpisodeMenu : WolfMenu
{
    const NE_X = 10;
    const NE_Y = 23;

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        labels.Clear(); itemStates.Clear();
        labels.Push("Episode 1\nEscape from Wolfenstein");
        labels.Push("Episode 2\nOperation: Eisenfaust");
        labels.Push("Episode 3\nDie, Fuhrer, Die!");
        labels.Push("Episode 4\nA Dark Secret");
        labels.Push("Episode 5\nTrail of the Madman");
        labels.Push("Episode 6\nConfront Fate");
        for (int i = 0; i < 6; i++)
            itemStates.Push(IT_NORMAL);
    }

    override void Drawer()
    {
        DrawBackground();
        // DrawNewEpisode (WL_MENU.C): full-height window, READHCOLOR title
        DrawWindowBox(NE_X - 4, NE_Y - 4, 320 - NE_X * 2 + 8,
                      200 - NE_Y * 2 + 8);
        String title = "Which episode to play?";
        WolfDraw.Text(big, 160 - big.StringWidth(title) / 2, 2, title,
                      WolfPal.Get(C_READH));
        DrawItems(NE_X, NE_Y, 88, 26);
        for (int i = 0; i < 6; i++)
            WolfDraw.Pic(NE_X + 32, NE_Y + i * 26,
                         String.Format("C_EPIS%d", i + 1));
        DrawGun(NE_X, NE_Y, 26);
    }

    override void OnChoose(int index)
    {
        Menu.SetMenu("WolfSkillMenu");
        // pass the episode through the live menu object
        Menu cur = Menu.GetCurrentMenu();
        if (cur is "WolfSkillMenu")
            WolfSkillMenu(cur).episode = index;
    }
}

// ---------------------------------------------------------------------------

class WolfSkillMenu : WolfMenu
{
    const NM_X = 50;
    const NM_Y = 100;

    int episode;

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        labels.Clear(); itemStates.Clear();
        labels.Push("Can I play, Daddy?");     itemStates.Push(IT_NORMAL);
        labels.Push("Don't hurt me.");         itemStates.Push(IT_NORMAL);
        labels.Push("Bring 'em on!");          itemStates.Push(IT_NORMAL);
        labels.Push("I am Death incarnate!");  itemStates.Push(IT_NORMAL);
        sel = 2;                               // STARTITEM: Bring 'em on!
    }

    override void Drawer()
    {
        DrawBackground();
        WolfDraw.Text(big, NM_X + 20, NM_Y - 32, "How tough are you?",
                      WolfPal.Get(C_READH));
        DrawWindowBox(NM_X - 5, NM_Y - 10, 225, 13 * 4 + 15);
        DrawItems(NM_X, NM_Y, 24, 13);
        // the BJ face for the hovered difficulty (DrawNewGameDiff)
        WolfDraw.Pic(NM_X + 185, NM_Y + 7,
                     String.Format("C_%s", sel == 0 ? "BABY"
                        : sel == 1 ? "EASY" : sel == 2 ? "NORMAL" : "HARD"));
        DrawGun(NM_X, NM_Y, 13);
    }

    override void OnChoose(int index)
    {
        // Reset score/lives play-side, then start through the engine's own
        // new-game path. ChangeLevel from the titlemap is NOT that: it
        // carries GS_TITLELEVEL into the new map — no status bar, any key
        // reopening the menu, the works.
        EventHandler.SendNetworkEvent("wolf_newgame", episode, index);
        Menu.StartGameDirect(false, false, null, episode, index);
        // belt and braces: make sure nothing of the stack survives
        Menu cur = Menu.GetCurrentMenu();
        while (cur != null)
        {
            cur.Close();
            cur = Menu.GetCurrentMenu();
        }
    }
}

// ---------------------------------------------------------------------------

// Read This! â€” the T_HELPART article through the existing renderer
class WolfReadMenu : WolfMenu
{
    WolfArticle article;

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        article = new("WolfArticle");
        if (!article.Init("HELPART.txt"))
            article = null;
    }

    override void Drawer()
    {
        if (article == null)
        {
            Close();
            return;
        }
        // the letterbox treatment: stone backdrop, page in the bevel
        WolfDraw.Backdrop("WALL022");   // wood: stone pages
                                        // clash on stone tiles
        double px = WolfDraw.Px();
        double sh = screen.GetHeight(), sw = screen.GetWidth();
        double ah = sh - 32 * px, aw = ah * (4.0 / 3.0);
        double ax = (sw - aw) / 2, ay = 16 * px;
        WolfDraw.BevelRing(ax, ay, aw, ah);
        article.SetRect(ax, ay, aw, ah);
        article.Draw();
    }

    override bool MenuEvent(int mkey, bool fromcontroller)
    {
        if (article == null)
            return Super.MenuEvent(mkey, fromcontroller);
        switch (mkey)
        {
        case MKEY_Left:
            article.PrevPage();
            return true;
        case MKEY_Right:
        case MKEY_Enter:
            if (!article.NextPage())
            {
                MenuSound("menu/backup");
                Close();
            }
            return true;
        case MKEY_Back:
            MenuSound("menu/backup");
            Close();
            return true;
        }
        return Super.MenuEvent(mkey, fromcontroller);
    }
}

// ---------------------------------------------------------------------------

// Message() (WL_MENU.C:3490): the grey message window with a black/
// HIGHLIGHT outline, used for the quit and end-game confirms. Wired in
// via gameinfo messageboxclass, so the engine's own confirm flows use it.
class WolfMessageBox : MessageBoxMenu
{
    Font big;

    // the full base signature: dropping cmd/native_handler is what broke
    // Quit->Yes (the handler that actually exits lives in those params)
    override void Init(Menu parent, String message, int messagemode,
                       bool playsound, Name cmd, voidptr native_handler)
    {
        Array<int> mpk;
        Bindings.GetAllKeysForCommand(mpk, "");
        String mb = Bindings.GetBinding(0x66);
        if (mb.IndexOf("wolf_mp_marker") == 0)
            message = "Restart into multiplayer?

"
                      "The launcher takes it from here.";
        Super.Init(parent, message, messagemode, playsound, cmd,
                   native_handler);
        big = Font.GetFont("wolfbig");
        // no engine dim (the purple wash): the original never confirms
        // over live gameplay — Confirm() runs on the red menu screen
        DontDim = true;
    }

    override void Drawer()
    {
        if (big == null || mMessage == null)
        {
            Super.Drawer();
            return;
        }
        // Opened from a menu: repaint the red menu screen (the engine
        // draws only the top menu). Opened over gameplay (the MLI
        // message): overlay the frozen view, as the original does.
        if (mParentMenu is "WolfMenu")
        {
            WolfDraw.WideBar(0, 200, 0x29);
            WolfDraw.WideBar(10, 24, 0);
            WolfDraw.WideBar(32, 1, 0x2c);
            WolfDraw.Pic(84, 0, "C_OPTS");
        }

        // measure the block in font units
        int h = 0, mw = 0;
        int n = mMessage.Count();
        for (int i = 0; i < n; i++)
        {
            int w = big.StringWidth(mMessage.StringAt(i));
            if (w > mw)
                mw = w;
            h += 13;
        }
        mw += 10;
        int x = 160 - mw / 2, y = 100 - h / 2;

        WolfMenu.DrawStaticWindow(x - 5, y - 5, mw + 10, h + 10);
        for (int i = 0; i < n; i++)
            WolfDraw.Text(big, x, y + i * 13, mMessage.StringAt(i),
                          WolfPal.Get(0));
    }
}
