// The Wolf option-widget set: toggle buttons (C_SELECTED/C_NOTSELECTED,
// the original Control screen's lit lamps), sliders in the ECWolf style
// (grey track, yellow block), multi-choice text values, and command rows.
// Pages assemble from these; the key-binding grid is its own pass.
//
// CVar access follows the engine's own option menus: GetCVar with the
// console player, SetInt/SetFloat from ui scope (single-player safe).

class WolfWidgetMenu : WolfMenu
{
    enum EKind { W_LABEL, W_TOGGLE, W_SLIDER, W_MULTI, W_COMMAND, W_BIND };

    Array<int> wKind;
    Array<String> wCVar;
    Array<double> wMin, wMax, wStep;
    Array<String> wChoices;         // W_MULTI: comma-separated values
    String title;
    int winX, winY, winW, winH;

    // Pages taller than MAXROWS rows scroll: the window box shrinks to
    // the visible slice and the cursor drags the view along. 9 rows
    // keeps the frame inside the 200-unit screen with the title above
    // and breathing room below (Modernization hit 12 rows - user
    // screenshot showed it overflowing the frame).
    const MAXROWS = 9;
    int scroll;

    int VisRows() { return min(labels.Size(), MAXROWS); }
    // effective box height: winH minus the hidden rows, so pages that
    // pad winH for extras (crosshair preview) keep their padding
    int EffH() { return winH - 13 * (labels.Size() - VisRows()); }

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        labels.Clear(); itemStates.Clear();
        wKind.Clear(); wCVar.Clear();
        wMin.Clear(); wMax.Clear(); wStep.Clear(); wChoices.Clear();
        // wide enough that the slider column never touches the labels
        winX = 24; winY = MENU_Y;
        winW = 320 - 48; winH = 13 * 4 + 6;
    }

    // ---- builders --------------------------------------------------------

    void AddRow(int kind, String label, String cvarName, int state)
    {
        labels.Push(label); itemStates.Push(state);
        wKind.Push(kind); wCVar.Push(cvarName);
        wMin.Push(0); wMax.Push(1); wStep.Push(1); wChoices.Push("");
    }

    void AddLabel(String label)   { AddRow(W_LABEL, label, "", IT_DISABLED); }
    void AddToggle(String label, String cvarName)
    {
        AddRow(W_TOGGLE, label, cvarName, IT_NORMAL);
    }
    void AddCommand(String label) { AddRow(W_COMMAND, label, "", IT_NORMAL); }
    void AddToggleV(String label, String cvarName, int onValue,
                    int offValue = 0)
    {
        AddRow(W_TOGGLE, label, cvarName, IT_NORMAL);
        wMax[wMax.Size() - 1] = onValue;
        wMin[wMin.Size() - 1] = offValue;
    }
    // a key-binding row: wCVar holds the +command
    void AddBindRow(String label, String cmd)
    {
        AddRow(W_BIND, label, cmd, IT_NORMAL);
    }
    void AddSlider(String label, String cvarName, double mn, double mx,
                   double st)
    {
        AddRow(W_SLIDER, label, cvarName, IT_NORMAL);
        wMin[wMin.Size() - 1] = mn;
        wMax[wMax.Size() - 1] = mx;
        wStep[wStep.Size() - 1] = st;
    }
    void AddMulti(String label, String cvarName, String choices)
    {
        AddRow(W_MULTI, label, cvarName, IT_NORMAL);
        wChoices[wChoices.Size() - 1] = choices;
    }

    // ---- cvar plumbing ---------------------------------------------------

    CVar GetCV(int i)
    {
        if (wCVar[i] == "")
            return null;
        // FindCVar, NOT GetCVar(player): GetCVar returns the per-player
        // userinfo VIEW of a user cvar - writes to it apply in-session
        // but are never archived, so every toggle silently reset on
        // relaunch (autotoggle probe: in-session 1, ini 0). The base
        // cvar is the archived one, and writing it propagates to the
        // userinfo copy exactly like a console `set` does.
        return CVar.FindCVar(wCVar[i]);
    }

    int ChoiceCount(int i)
    {
        Array<String> parts;
        wChoices[i].Split(parts, ",");
        return parts.Size();
    }

    String ChoiceName(int i, int v)
    {
        Array<String> parts;
        wChoices[i].Split(parts, ",");
        if (v < 0 || v >= parts.Size())
            return "?";
        return parts[v];
    }

    // ---- drawing ---------------------------------------------------------

    override void Drawer()
    {
        DrawBackground();
        if (title != "")
            WolfDraw.Text(big, 160 - big.StringWidth(title) / 2, 4, title,
                          WolfPal.Get(C_READH));

        // keep the selection inside the visible slice (works no matter
        // how sel moved: keys, wrap-around, or mouse hover)
        int n = labels.Size();
        if (n > MAXROWS)
        {
            if (sel < scroll)
                scroll = sel;
            if (sel >= scroll + MAXROWS)
                scroll = sel - MAXROWS + 1;
            scroll = clamp(scroll, 0, n - MAXROWS);
        }
        else
            scroll = 0;

        DrawWindowBox(winX, winY - 3, winW, EffH());

        hitX = winX + 8; hitY = winY; hitPitch = 13;
        for (int r = 0; r < VisRows(); r++)
        {
            int i = r + scroll;
            int y = winY + r * 13;
            int pal = itemStates[i] == IT_DISABLED ? C_READH
                    : (i == sel ? C_HILITE : C_TEXT);
            int tx = winX + 8;

            if (wKind[i] == W_TOGGLE)
            {
                CVar cv = GetCV(i);
                bool on = cv != null && cv.GetInt() == int(wMax[i]);
                WolfDraw.Pic(tx, y + 2, on ? "C_SEL" : "C_NOTSEL");
            }
            if (wKind[i] != W_LABEL)
                tx += 30;
            WolfDraw.Text(big, tx, y, labels[i], WolfPal.Get(pal));

            if (wKind[i] == W_SLIDER)
            {
                CVar cv = GetCV(i);
                double v = cv == null ? wMin[i] : cv.GetFloat();
                double frac = clamp((v - wMin[i]) / (wMax[i] - wMin[i]),
                                    0, 1);
                int bx = winX + winW - 112, bw = 100;
                // sunken track: dark top/left, light bottom/right
                WolfDraw.Bar(bx, y + 3, bw, 7, 0x1B);
                WolfDraw.Bar(bx, y + 3, bw, 1, 0x1F);
                WolfDraw.Bar(bx, y + 3, 1, 7, 0x1F);
                WolfDraw.Bar(bx, y + 9, bw, 1, C_HILITE);
                WolfDraw.Bar(bx + bw - 1, y + 3, 1, 7, C_HILITE);
                // raised block: light top/left, gold shadow bottom/right
                int kx = bx + int(frac * (bw - 12));
                WolfDraw.Bar(kx, y + 2, 12, 9, C_READH);
                WolfDraw.Bar(kx, y + 2, 12, 1, 0x10);
                WolfDraw.Bar(kx, y + 2, 1, 9, 0x10);
                WolfDraw.Bar(kx, y + 10, 12, 1, C_READ);
                WolfDraw.Bar(kx + 11, y + 2, 1, 9, C_READ);
            }
            else if (wKind[i] == W_BIND)
            {
                Array<int> bkeys;
                Bindings.GetAllKeysForCommand(bkeys, wCVar[i]);
                String kn = (i == sel && waitingBind) ? "???"
                    : bkeys.Size() == 0 ? "---"
                    : KeyBindings.NameKeys(bkeys[0], 0);
                if (kn.Length() > 7)
                    kn = kn.Left(7);
                WolfDraw.Text(big, winX + winW - 10
                              - big.StringWidth(kn), y, kn,
                              WolfPal.Get(itemStates[i] == IT_DISABLED
                                          ? WolfDraw.C_DEACTIVE_() : C_READH));
            }
            else if (wKind[i] == W_MULTI)
            {
                CVar cv = GetCV(i);
                int v = cv == null ? 0 : cv.GetInt();
                String val = ChoiceName(i, v);
                WolfDraw.Text(big, winX + winW - 10
                              - big.StringWidth(val), y, val,
                              WolfPal.Get(C_READH));
            }
        }
        // cursor base shifted up by the hidden rows so it tracks the
        // on-screen position of sel
        DrawGun(winX - 24 + 2, winY - scroll * 13, 13);

        // scroll arrows float in the gutter outside the frame's right
        // edge (mirroring the gun cursor's gutter on the left), so they
        // never collide with the right-aligned key/value column
        if (scroll > 0)
            DrawScrollArrow(winX + winW + 9, winY + 1, false);
        if (scroll + MAXROWS < n)
            DrawScrollArrow(winX + winW + 9, winY + EffH() - 12, true);
    }

    // small triangle built from bars, same gold as the value text
    void DrawScrollArrow(int cx, int y, bool down)
    {
        for (int r = 0; r < 3; r++)
        {
            int w = down ? 10 - r * 4 : 2 + r * 4;
            WolfDraw.Bar(cx - w / 2, y + r * 2, w, 2, C_READH);
        }
    }

    // ---- input -----------------------------------------------------------

    virtual void OnToggled(int i, int newValue) {}

    virtual void Adjust(int i, int dir)
    {
        CVar cv = GetCV(i);
        if (cv == null)
            return;
        if (wKind[i] == W_TOGGLE)
        {
            // NOTE: server cvars apply DEFERRED - never re-read right
            // after SetInt (that inverted the freelook companion once)
            int target = cv.GetInt() == int(wMax[i]) ? int(wMin[i])
                                                     : int(wMax[i]);
            cv.SetInt(target);
            OnToggled(i, target);
            MenuSound("menu/change");
        }
        else if (wKind[i] == W_SLIDER)
        {
            cv.SetFloat(clamp(cv.GetFloat() + dir * wStep[i],
                              wMin[i], wMax[i]));
            MenuSound("menu/change");
        }
        else if (wKind[i] == W_MULTI)
        {
            int n = ChoiceCount(i);
            cv.SetInt((cv.GetInt() + dir + n) % n);
            MenuSound("menu/change");
        }
    }

    bool waitingBind;
    int pendingKey;

    void StartBind()
    {
        if (itemStates[sel] == IT_DISABLED)
            return;
        waitingBind = true;
        WolfEnterKeyW ek = new("WolfEnterKeyW");
        ek.Init(self, self);
        ek.ActivateMenu();
    }

    void SendKey(int key) { pendingKey = key; }

    // Mouse: hover selects; click toggles lamps and cycles values;
    // sliders set to the clicked position and DRAG while held.
    bool dragging;

    override bool MouseEvent(int type, int x, int y)
    {
        // A mouse event can arrive BEFORE the first Drawer has set
        // hitPitch (one-frame window on menu open): division by zero,
        // VM abort, session torn down. This was Eric's months... er,
        // days-long "settings menu restarts my game" glitch - keyboard
        // hunts never caught it because only the MOUSE path divides.
        // The base class guard (wolfmenu.zs:195) existed all along;
        // this override just never inherited the lesson.
        if (hitPitch <= 0 || labels.Size() == 0)
            return false;
        double ux = (x - WolfDraw.OrgX()) / WolfDraw.ScaleX();
        double uy = y / WolfDraw.ScaleY();
        // screen row -> list row through the scroll offset; rows below
        // the visible slice are frame, not items
        int row = int((uy - hitY + 2) / hitPitch);
        int idx = row + scroll;
        bool onRow = row >= 0 && row < VisRows()
                     && idx < labels.Size()
                     && uy >= hitY - 2
                     && itemStates[idx] != IT_DISABLED;

        if (type == MOUSE_Release)
            dragging = false;

        if (onRow && !dragging && idx != sel)
        {
            sel = idx;
            MenuSound("menu/cursor");
        }

        // slider: absolute position, live while dragging
        int si = dragging ? sel : idx;
        if ((type == MOUSE_Click || (type == MOUSE_Move && dragging))
            && onRow || (dragging && type == MOUSE_Move))
        {
            if (si >= 0 && si < wKind.Size() && wKind[si] == W_SLIDER)
            {
                if (type == MOUSE_Click)
                    dragging = true;
                CVar cv = GetCV(si);
                if (cv != null)
                {
                    double bx = winX + winW - 112, bw = 100;
                    double frac = clamp((ux - bx - 6) / (bw - 12), 0, 1);
                    double v = wMin[si] + frac * (wMax[si] - wMin[si]);
                    v = wMin[si]
                        + round((v - wMin[si]) / wStep[si]) * wStep[si];
                    cv.SetFloat(clamp(v, wMin[si], wMax[si]));
                }
                return true;
            }
        }

        if (type == MOUSE_Release && onRow)
        {
            if (wKind[idx] == W_COMMAND)
            {
                MenuSound("menu/advance");
                OnChoose(idx);
            }
            else if (wKind[idx] == W_BIND)
                StartBind();
            else
                Adjust(idx, 1);         // lamps flip, values cycle
        }
        return true;
    }

    override bool MenuEvent(int mkey, bool fromcontroller)
    {
        switch (mkey)
        {
        case MKEY_Left:  Adjust(sel, -1); return true;
        case MKEY_Right: Adjust(sel, 1);  return true;
        case MKEY_Enter:
            if (wKind[sel] == W_COMMAND)
            {
                MenuSound("menu/advance");
                OnChoose(sel);
            }
            else if (wKind[sel] == W_BIND)
                StartBind();
            else
                Adjust(sel, 1);
            return true;
        case MKEY_Input:
        {
            waitingBind = false;
            Bindings.UnbindACommand(wCVar[sel]);
            Bindings.SetBind(pendingKey, wCVar[sel]);
            MenuSound("menu/change");
            return true;
        }
        case MKEY_Abort:
            waitingBind = false;
            return true;
        }
        return Super.MenuEvent(mkey, fromcontroller);
    }
}

// ---------------------------------------------------------------------------

class WolfControlMenu : WolfWidgetMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Control Setup";
        AddToggle("Always Run", "cl_run");
        AddToggle("Mouse Enabled", "use_mouse");
        AddCommand("Mouse Sensitivity");
        AddToggle("Joystick Enabled", "use_joystick");
        AddCommand("Customize controls");
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }

    override void OnChoose(int index)
    {
        if (labels[index] == "Mouse Sensitivity")
            Menu.SetMenu("WolfMouseMenu");
        else if (labels[index] == "Customize controls")
            Menu.SetMenu("WolfBindGrid");
    }
}

class WolfMouseMenu : WolfWidgetMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Adjust Mouse Sensitivity";
        // this engine has no mouse_sensitivity cvar; m_yaw is the knob
        AddSlider("Sensitivity", "m_yaw", 0.25, 3.0, 0.25);
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }
}

class WolfSoundMenu : WolfWidgetMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Sound Options";
        AddSlider("Sound Volume", "snd_sfxvolume", 0, 1.0, 0.1);
        AddSlider("Music Volume", "snd_musicvolume", 0, 1.0, 0.1);
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }
}

class WolfDisplayMenu : WolfWidgetMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Display Options";
        AddToggle("Fullscreen", "vid_fullscreen");
        AddSlider("Screen Size", "screenblocks", 4, 11, 1);
        AddSlider("Brightness", "vid_gamma", 0.75, 2.0, 0.05);
        AddCommand("Advanced Video Options");
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }

    override void OnChoose(int index)
    {
        if (labels[index] == "Advanced Video Options")
            Menu.SetMenu("VideoOptions");        // engine page, recolored
    }
}

class WolfAutomapMenu : WolfWidgetMenu
{
    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        title = "Automap Options";
        AddMulti("Overlay", "am_overlay", "Off,On,Both");
        AddMulti("Rotate", "am_rotate", "No,Yes,Overlay only");
        AddToggle("Floor Textures", "am_textured");
        AddToggle("Show Totals", "am_showtotaltime");
        winH = 13 * labels.Size() + 6;
        sel = 0;
    }
}

class WolfEnterKeyW : Menu
{
    WolfWidgetMenu mOwner;

    void Init(Menu parent, WolfWidgetMenu owner)
    {
        Super.Init(parent);
        mOwner = owner;
        menuactive = Menu.WaitKey;
        DontDim = true;
    }

    override bool TranslateKeyboardEvents() { return false; }

    override bool OnInputEvent(InputEvent ev)
    {
        if (ev.type == InputEvent.Type_KeyDown)
        {
            mOwner.SendKey(ev.KeyScan);
            menuactive = Menu.On;
            Close();
            mParentMenu.MenuEvent(
                ev.KeyScan == InputEvent.KEY_ESCAPE ? Menu.MKEY_Abort
                                                    : Menu.MKEY_Input, 0);
            return true;
        }
        return false;
    }

    override void Drawer() { mParentMenu.Drawer(); }
}
