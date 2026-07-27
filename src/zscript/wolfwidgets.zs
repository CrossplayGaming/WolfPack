// The Wolf option-widget set: toggle buttons (C_SELECTED/C_NOTSELECTED,
// the original Control screen's lit lamps), sliders in the ECWolf style
// (grey track, yellow block), multi-choice text values, and command rows.
// Pages assemble from these; the key-binding grid is its own pass.
//
// CVar access follows the engine's own option menus: GetCVar with the
// console player, SetInt/SetFloat from ui scope (single-player safe).

class WolfWidgetMenu : WolfMenu
{
    enum EKind { W_LABEL, W_TOGGLE, W_SLIDER, W_MULTI, W_COMMAND };

    Array<int> wKind;
    Array<String> wCVar;
    Array<double> wMin, wMax, wStep;
    Array<String> wChoices;         // W_MULTI: comma-separated values
    String title;
    int winX, winY, winW, winH;

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
    void AddToggleV(String label, String cvarName, int onValue)
    {
        AddRow(W_TOGGLE, label, cvarName, IT_NORMAL);
        wMax[wMax.Size() - 1] = onValue;
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
        return CVar.GetCVar(wCVar[i], players[consoleplayer]);
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
        DrawWindowBox(winX, winY - 3, winW, winH);

        hitX = winX + 8; hitY = winY; hitPitch = 13;
        for (int i = 0; i < labels.Size(); i++)
        {
            int y = winY + i * 13;
            int pal = itemStates[i] == IT_DISABLED ? C_READH
                    : (i == sel ? C_HILITE : C_TEXT);
            int tx = winX + 8;

            if (wKind[i] == W_TOGGLE)
            {
                CVar cv = GetCV(i);
                bool on = cv != null && cv.GetInt() != 0;
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
        DrawGun(winX - 24 + 2, winY, 13);
    }

    // ---- input -----------------------------------------------------------

    virtual void Adjust(int i, int dir)
    {
        CVar cv = GetCV(i);
        if (cv == null)
            return;
        if (wKind[i] == W_TOGGLE)
        {
            cv.SetInt(cv.GetInt() != 0 ? 0 : int(wMax[i]));
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

    // Mouse: hover selects; click toggles lamps and cycles values;
    // sliders set to the clicked position and DRAG while held.
    bool dragging;

    override bool MouseEvent(int type, int x, int y)
    {
        double ux = (x - WolfDraw.OrgX()) / WolfDraw.ScaleX();
        double uy = y / WolfDraw.ScaleY();
        int idx = int((uy - hitY + 2) / hitPitch);
        bool onRow = idx >= 0 && idx < labels.Size()
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
            else
                Adjust(sel, 1);
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
