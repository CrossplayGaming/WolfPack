// WolfAttract — the attract sequence (DemoLoop, WL_MAIN.C:1411-1545).
//
// The original's cycle: the PG13 advisory once at startup, then forever
// title page (15 s) -> credits (10 s) -> high scores (10 s) -> a recorded
// demo. Any key drops into the main menu.
//
// Implemented as a Menu rather than a render overlay: on a title level a
// StaticEventHandler's RenderOverlay can Dim, but its DrawTexture calls
// never reach the screen, so the pictures simply never appeared. Menus
// draw through the normal 2D path and get input for free.
//
// Deviation: demo playback is not implemented. The recorded demos replay
// player input through the original's exact simulation, which belongs with
// the DOSBox determinism work, so the cycle runs high scores -> title.
class WolfAttractMenu : GenericMenu
{
    enum EPage { PG_ADVISORY, PG_TITLE, PG_CREDITS, PG_SCORES };

    int page, timer;

    // IN_UserInput(TickBase * n): TickBase is 70 Hz, so these are seconds
    const ADVISORY_TICS = 7 * 35;
    const TITLE_TICS    = 15 * 35;
    const CREDITS_TICS  = 10 * 35;
    const SCORES_TICS   = 10 * 35;

    override void Init(Menu parent)
    {
        Super.Init(parent);
        page = PG_ADVISORY;
        timer = ADVISORY_TICS;
        DontDim = true;
    }

    override void Ticker()
    {
        if (--timer > 0)
            return;
        // the advisory shows once at startup and is not part of the cycle
        if (page == PG_ADVISORY || page == PG_SCORES)
        {
            page = PG_TITLE;
            timer = TITLE_TICS;
        }
        else if (page == PG_TITLE)
        {
            page = PG_CREDITS;
            timer = CREDITS_TICS;
        }
        else
        {
            page = PG_SCORES;
            timer = SCORES_TICS;
        }
    }

    override void Drawer()
    {
        screen.Dim(Color(0, 0, 0), 1.0, 0, 0,
                   screen.GetWidth(), screen.GetHeight());
        if (page == PG_ADVISORY)
        {
            // PG13 (WL_INTER.C:310): bar colour 0x82, pic at (216,110)
            WolfDraw.Bar(0, 0, 320, 200, 0x82);
            WolfDraw.Pic(216, 110, "PG13");
        }
        else if (page == PG_TITLE)
            WolfDraw.Pic(0, 0, "TITLEPIC");
        else if (page == PG_CREDITS)
            WolfDraw.Pic(0, 0, "CREDITS");
        else
            WolfHighScores.Draw();
    }

    // any key enters the menu, exactly as IN_UserInput's return does
    override bool OnInputEvent(InputEvent ev)
    {
        if (ev.type == InputEvent.Type_KeyDown)
        {
            Menu.SetMenu("MainMenu");
            return true;
        }
        return false;
    }

    override bool MenuEvent(int mkey, bool fromcontroller)
    {
        Menu.SetMenu("MainMenu");
        return true;
    }
}

// Puts the attract menu up as soon as the title map is running.
class WolfAttract : StaticEventHandler
{
    ui bool opened;

    clearscope static bool IsTitle()
    {
        return Level.MapName == "TITLEMAP";
    }

    override void WorldLoaded(WorldEvent e)
    {
        if (!IsTitle())
            return;
        S_ChangeMusic("NAZI_NOR", 0, true);      // INTROSONG (WL_MENU.H:37)
    }

    override void UiTick()
    {
        if (!IsTitle())
        {
            opened = false;
            return;
        }
        if (!opened && Menu.GetCurrentMenu() == null)
        {
            opened = true;
            Menu.SetMenu("WolfAttractMenu");
        }
    }
}

// Shared drawing for the front end, in the original's 320x200 space
// mapped to a 4:3 area of full height, centred.
//
// It uses REAL pixel coordinates with an explicit destination size,
// deliberately avoiding DTA_320x200 and the DTA_Virtual* tags: measuring
// showed those scale differently inside a StatusScreen than inside a
// Menu, and neither matches hand-rolled scaling. Real pixels are the one
// transform that means the same thing in every context.
class WolfDraw
{
    static double ScaleX()
    {
        return screen.GetHeight() * (4.0 / 3.0) / 320.0;
    }

    static double ScaleY()
    {
        return screen.GetHeight() / 200.0;
    }

    static double OrgX()
    {
        return (screen.GetWidth() - screen.GetHeight() * (4.0 / 3.0)) / 2;
    }

    static void Bar(int x, int y, int w, int h, int palIndex)
    {
        double sx = ScaleX(), sy = ScaleY();
        screen.Dim(WolfPal.Get(palIndex), 1.0,
                   int(OrgX() + x * sx), int(y * sy),
                   int(w * sx + 1), int(h * sy + 1));
    }

    static void Pic(double x, double y, String lump)
    {
        TextureID t = TexMan.CheckForTexture(lump, TexMan.Type_MiscPatch);
        if (!t.IsValid())
            return;
        // same virtual screen as Text(), so pictures and text that share a
        // column actually line up
        screen.DrawTexture(t, true, (VirtW() - 320.0) / 2 + x, y,
                           DTA_VirtualWidthF, VirtW(),
                           DTA_VirtualHeightF, 200.0);
    }

    // DrawText ignores DTA_ScaleX/Y, so text uses a virtual screen instead:
    // wide enough to span the display, with 320 units across the 4:3 area,
    // which lands on the same rectangle the pictures use.
    static double VirtW()
    {
        return 320.0 * screen.GetWidth() / (screen.GetHeight() * (4.0 / 3.0));
    }

    static void Text(Font fnt, double x, double y, String s, Color c)
    {
        screen.DrawText(fnt, Font.CR_UNTRANSLATED,
                        (VirtW() - 320.0) / 2 + x, y, s,
                        DTA_VirtualWidthF, VirtW(),
                        DTA_VirtualHeightF, 200.0,
                        DTA_ColorOverlay, 0xFF000000 | c);
    }
}
