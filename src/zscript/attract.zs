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
        // the advisory runs once per boot; "Back to Demo" lands on the
        // title page, as US_ControlPanel's exit does
        WolfAttract h = WolfAttract(StaticEventHandler.Find("WolfAttract"));
        if (h != null && h.seenAdvisory)
        {
            page = PG_TITLE;
            timer = TITLE_TICS;
        }
        else
        {
            page = PG_ADVISORY;
            timer = ADVISORY_TICS;
        }
        if (h != null)
            h.seenAdvisory = true;
        DontDim = true;
        S_ChangeMusic("NAZI_NOR", 0, true);  // INTROSONG
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
            WolfDraw.WideBar(0, 200, 0x82);
            WolfDraw.Pic(216, 110, "PG13");
        }
        else if (page == PG_TITLE)
            WolfDraw.FramedPic("TITLEPIC");
        else if (page == PG_CREDITS)
            WolfDraw.FramedPic("CREDITS");
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
    ui bool seenAdvisory;

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

    // Background fills span the whole display rather than stopping at the
    // 4:3 box: the original's flat-coloured screens extend to 16:9 with no
    // loss of fidelity, and pillarboxing them just wastes the panel.
    static void WideBar(int y, int h, int palIndex)
    {
        double sy = ScaleY();
        screen.Dim(WolfPal.Get(palIndex), 1.0, 0, int(y * sy),
                   screen.GetWidth(), int(h * sy + 1));
    }

    static void Bar(int x, int y, int w, int h, int palIndex)
    {
        double sx = ScaleX(), sy = ScaleY();
        screen.Dim(WolfPal.Get(palIndex), 1.0,
                   int(OrgX() + x * sx), int(y * sy),
                   int(w * sx + 1), int(h * sy + 1));
    }

    // CALIBRATED 2026-07-27 (charter DRAW-001): with known DestWidths
    // measured against a window-sized reference rect in one frame,
    // DTA_DestWidthF and real-pixel positions are honoured EXACTLY. A
    // virtual screen maps onto the centred 4:3 box, NOT the display — so
    // virtual 320x200 is also correct, while a widened virtual width
    // (my old VirtW) squeezed everything by 320/VirtW into a square.
    static void Pic(double x, double y, String lump)
    {
        TextureID t = TexMan.CheckForTexture(lump, TexMan.Type_MiscPatch);
        if (!t.IsValid())
            return;
        int tw, th;
        [tw, th] = TexMan.GetSize(t);
        double sx = ScaleX(), sy = ScaleY();
        screen.DrawTexture(t, true, OrgX() + x * sx, y * sy,
                           DTA_DestWidthF, tw * sx,
                           DTA_DestHeightF, th * sy);
    }

    static void Text(Font fnt, double x, double y, String s, Color c)
    {
        screen.DrawText(fnt, Font.CR_UNTRANSLATED, x, y, s,
                        DTA_VirtualWidth, 320, DTA_VirtualHeight, 200,
                        DTA_ColorOverlay, 0xFF000000 | c);
    }

    // ---- the Keen letterbox treatment --------------------------------

    // one on-screen "game pixel": whole pixels so the bevel reads as
    // deliberate pixel art rather than an anti-aliased border
    static int Px()
    {
        return max(1, int(screen.GetHeight() / 200.0));
    }

    // the game's own stone tiled across the window at game-pixel zoom,
    // darkened so the framed art stays the focus
    static void Backdrop()
    {
        TextureID t = TexMan.CheckForTexture("WALL000", TexMan.Type_Any);
        if (!t.IsValid())
            return;
        double step = 64.0 * Px();
        for (double y = 0; y < screen.GetHeight(); y += step)
            for (double x = 0; x < screen.GetWidth(); x += step)
                screen.DrawTexture(t, true, x, y,
                                   DTA_DestWidthF, step, DTA_DestHeightF, step,
                                   DTA_ColorOverlay, Color(178, 0, 0, 0));
    }

    // one bevel layer: bottom/right first, top/left over the corners
    static void Edges(double x, double y, double w, double h, double t,
                      Color tl, Color br)
    {
        screen.Dim(br, 1.0, int(x + w - t), int(y), int(t + 1), int(h + 1));
        screen.Dim(br, 1.0, int(x), int(y + h - t), int(w + 1), int(t + 1));
        screen.Dim(tl, 1.0, int(x), int(y), int(w + 1), int(t + 1));
        screen.Dim(tl, 1.0, int(x), int(y), int(t + 1), int(h + 1));
    }

    // the five-layer bevel around an arbitrary real-pixel rect
    static void BevelRing(double ax, double ay, double aw, double ah)
    {
        double px = Px();
        Color dark  = WolfPal.Get(0x1F);     // (32,32,32)
        Color light = WolfPal.Get(0x17);     // (142,142,142)
        Color face  = WolfPal.Get(0x1B);     // (85,85,85)
        Color black = WolfPal.Get(0);

        double x = ax, y = ay, w = aw, h = ah;
        // grow outward, drawing each ring
        x -= px;     y -= px;     w += 2*px;   h += 2*px;
        Edges(x, y, w, h, px, black, black);          // seam
        x -= 2*px;   y -= 2*px;   w += 4*px;   h += 4*px;
        Edges(x, y, w, h, 2*px, dark, light);         // inset bevel
        x -= 4*px;   y -= 4*px;   w += 8*px;   h += 8*px;
        Edges(x, y, w, h, 4*px, face, face);          // flat face
        x -= 2*px;   y -= 2*px;   w += 4*px;   h += 4*px;
        Edges(x, y, w, h, 2*px, light, dark);         // raised bevel
        x -= px;     y -= px;     w += 2*px;   h += 2*px;
        Edges(x, y, w, h, px, black, black);          // outline

    }

    // Full-frame art sunk into a chunky five-layer bevel over the tiled
    // stone — the Keen 4-6 letterbox treatment (k13_present_frame), with
    // the EGA browns swapped for the Wolf palette's grey ramp. Layers from
    // the art outward: black seam, inset bevel (art sits sunken), flat
    // face, raised outer bevel, black outline.
    static void FramedPic(String lump)
    {
        TextureID t = TexMan.CheckForTexture(lump, TexMan.Type_MiscPatch);
        if (!t.IsValid())
            return;
        Backdrop();

        double px = Px();
        double sh = screen.GetHeight(), sw = screen.GetWidth();
        double ah = sh - 32 * px;            // reserve 16 game px per side
        double aw = ah * (4.0 / 3.0);        // art keeps its 4:3 box
        double ax = (sw - aw) / 2, ay = 16 * px;

        // a few steps down the grey ramp from the first pass, so the frame
        // sits closer to the darkened stone instead of popping off it
        BevelRing(ax, ay, aw, ah);

        screen.DrawTexture(t, true, ax, ay,
                           DTA_DestWidthF, aw, DTA_DestHeightF, ah);
    }
}
