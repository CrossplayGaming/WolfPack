// The Customize key grid, ECWolf layout: Control | Key | Mse | Joy
// columns, capture on Enter/click (whatever input arrives fills its
// natural column - bindings are unified in this engine), Delete clears.
// Capture follows the engine's own EnterKey idiom: a pushed menu in
// WaitKey mode feeds the raw scan back as MKEY_Input.

class WolfBindGrid : WolfMenu
{
    Array<String> cmds;
    bool waiting;
    int pendingKey;

    const COL_KEY = 168;
    const COL_MSE = 222;
    const COL_JOY = 262;

    override void Init(Menu parent, ListMenuDescriptor desc)
    {
        Super.Init(parent, desc);
        labels.Clear(); itemStates.Clear(); cmds.Clear();
        AddBind("Forward",      "+forward");
        AddBind("Backward",     "+back");
        AddBind("Strafe Left",  "+moveleft");
        AddBind("Strafe Right", "+moveright");
        AddBind("Turn Left",    "+left");
        AddBind("Turn Right",   "+right");
        AddBind("Attack",       "+attack");
        AddBind("Open Door",    "+use");
        AddBind("Strafe",       "+strafe");
        AddBind("Run",          "+speed");
        sel = 0;
    }

    void AddBind(String label, String cmd)
    {
        labels.Push(label); itemStates.Push(IT_NORMAL); cmds.Push(cmd);
    }

    // first bound key of each class, named short
    String, String, String KeyCols(String cmd)
    {
        Array<int> keys;
        Bindings.GetAllKeysForCommand(keys, cmd);
        String kb = "", ms = "", jy = "";
        for (int i = 0; i < keys.Size(); i++)
        {
            int k = keys[i];
            String nm = KeyBindings.NameKeys(k, 0);
            if (nm.Length() > 4)
                nm = nm.Left(4);
            if (k < 0x100)
            {
                if (kb == "") kb = nm;
            }
            else if (k < 0x108 || (k >= 0x198 && k <= 0x19B))
            {
                if (ms == "") ms = nm;
            }
            else if (jy == "")
                jy = nm;
        }
        return kb, ms, jy;
    }

    override void Drawer()
    {
        DrawBackground();
        WolfDraw.WideBar(10, 24, 0);
        WolfDraw.WideBar(32, 1, C_STRIPE);
        WolfDraw.Pic(84, 0, "C_CUSTOM");

        // yellow column headers (ECWolf layout)
        WolfDraw.Text(big, 40, 40, "Control", WolfPal.Get(C_READH));
        WolfDraw.Text(big, COL_KEY, 40, "Key", WolfPal.Get(C_READH));
        WolfDraw.Text(big, COL_MSE, 40, "Mse", WolfPal.Get(C_READH));
        WolfDraw.Text(big, COL_JOY, 40, "Joy", WolfPal.Get(C_READH));

        int wy = 56;
        DrawWindowBox(28, wy - 3, 320 - 56, 13 * labels.Size() + 6);
        hitX = 36; hitY = wy; hitPitch = 13;

        for (int i = 0; i < labels.Size(); i++)
        {
            int y = wy + i * 13;
            int pal = i == sel ? (waiting ? 0x10 : C_HILITE) : C_TEXT;
            WolfDraw.Text(big, 40, y, labels[i], WolfPal.Get(pal));

            if (i == sel && waiting)
            {
                WolfDraw.Text(big, COL_KEY, y, "???",
                              WolfPal.Get(C_READH));
                continue;
            }
            String kb, ms, jy;
            [kb, ms, jy] = KeyCols(cmds[i]);
            WolfDraw.Text(big, COL_KEY, y, kb, WolfPal.Get(pal));
            WolfDraw.Text(big, COL_MSE, y, ms, WolfPal.Get(pal));
            WolfDraw.Text(big, COL_JOY, y, jy, WolfPal.Get(pal));
        }
        DrawGun(6, wy, 13);
    }

    override void OnChoose(int index)
    {
        waiting = true;
        WolfEnterKey ek = new("WolfEnterKey");
        ek.Init(self, self);
        ek.ActivateMenu();
    }

    void SendKey(int key) { pendingKey = key; }

    override bool MenuEvent(int mkey, bool fromcontroller)
    {
        if (mkey == MKEY_Input)
        {
            waiting = false;
            Bindings.SetBind(pendingKey, cmds[sel]);
            MenuSound("menu/change");
            return true;
        }
        if (mkey == MKEY_Abort)
        {
            waiting = false;
            return true;
        }
        if (mkey == MKEY_Clear)
        {
            Bindings.UnbindACommand(cmds[sel]);
            MenuSound("menu/backup");
            return true;
        }
        return Super.MenuEvent(mkey, fromcontroller);
    }
}

class WolfEnterKey : Menu
{
    WolfBindGrid mOwner;

    void Init(Menu parent, WolfBindGrid owner)
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
