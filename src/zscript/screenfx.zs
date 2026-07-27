// Get Psyched loading screen (PreloadGraphics, WL_INTER.C:995-1017) and
// the palette flashes (UpdatePaletteShifts, WL_PLAY.C:1054-1215).
//
// Flash math: the source builds shifted palettes by lerping every colour
// toward a target — red shifts push R to 64 and G/B to 0, white shifts
// push all three to 64 — by i/STEPS. That is exactly a screen blend
// toward pure red (or white) with alpha i/STEPS, which is how it is
// drawn here.
//   FLASH-001 bonus: count = NUMWHITESHIFTS(3) * WHITETICS(6) = 18 tics;
//                    index = count/6 + 1 capped 3; alpha = index/20
//   FLASH-002 damage: count += damage taken; index = count/10 + 1 capped
//                    NUMREDSHIFTS(6); alpha = index/8; count -= tics
//   FLASH-003 red wins over white
class WolfScreenFX : StaticEventHandler
{
    int psychedTics;
    bool psyched;

    const PSYCHED_TICS = 35;        // IN_UserInput(70) at 70Hz = 1 s

    clearscope static WolfScreenFX Get()
    {
        return WolfScreenFX(StaticEventHandler.Find("WolfScreenFX"));
    }

    override void WorldLoaded(WorldEvent e)
    {
        // the source skips "Get Psyched" when re-entering after a death
        WolfGameState gs = WolfGameState.Get();
        if (gs != null && gs.skipPsyched)
        {
            gs.skipPsyched = false;
            psyched = false;
            return;
        }
        psyched = true;
        psychedTics = PSYCHED_TICS;
        Level.SetFrozen(true);
    }

    override void WorldTick()
    {
        if (!psyched)
            return;
        psychedTics--;
        if (psychedTics <= 0)
        {
            psyched = false;
            Level.SetFrozen(false);
        }
    }

    override void RenderOverlay(RenderEvent e)
    {
        int w = screen.GetWidth(), h = screen.GetHeight();
        int viewH = h;
        CVar sb = CVar.GetCVar("screenblocks", players[consoleplayer]);
        if (sb != null && sb.GetInt() < 11)
            viewH = int(h * 160.0 / 200.0);

        if (psyched)
        {
            DrawPsyched(w, viewH);
            return;
        }

        // --- palette flashes ---
        WolfPlayer p = WolfPlayer(players[consoleplayer].mo);
        if (p == null)
            return;
        if (p.damageCount > 0)                      // FLASH-002/003
        {
            int idx = min(6, p.damageCount / 10 + 1);
            screen.Dim(Color(255, 0, 0), idx / 8.0, 0, 0, w, viewH);
        }
        else if (p.bonusCount > 0)                  // FLASH-001
        {
            int idx = min(3, p.bonusCount / 6 + 1);
            screen.Dim(Color(255, 255, 255), idx / 20.0, 0, 0, w, viewH);
        }
    }

    // PreloadGraphics: view filled with palette 127, GETPSYCHEDPIC at
    // cell (6,56), and a 2px progress bar across the window bottom.
    ui void DrawPsyched(int w, int viewH)
    {
        screen.Dim(Color(0, 65, 65), 1.0, 0, 0, w, viewH);

        // One explicit transform for both the pic and the bar so they
        // stay aligned: uniform scale, 320x200 centred horizontally.
        double sc = screen.GetHeight() / 200.0;
        double xoff = (w - 320 * sc) / 2;

        TextureID t = TexMan.CheckForTexture("PSYCHED", TexMan.Type_MiscPatch);
        Vector2 tsz = TexMan.GetScaledSize(t);
        screen.DrawTexture(t, false, xoff + 48 * sc, 56 * sc,
                           DTA_DestWidth, int(tsz.X * sc),
                           DTA_DestHeight, int(tsz.Y * sc));

        // window: X=160-14*8, Y=80-3*8, W=28*8, H=48; bar inset 5, 2 tall
        double frac = 1.0 - double(psychedTics) / PSYCHED_TICS;
        int bx = 48 + 5, by = 56 + 48 - 3, bw = 28 * 8 - 10;
        screen.Dim(Color(0, 0, 0), 1.0, int(xoff + bx * sc), int(by * sc),
                   int(bw * sc), int(2 * sc + 1));
        int fw = int(bw * frac);
        if (fw > 0)
        {
            // source uses palette 0x37 with a 0x32 highlight row
            screen.Dim(Color(120, 172, 120), 1.0,
                       int(xoff + bx * sc), int(by * sc),
                       int(fw * sc), int(2 * sc + 1));
            screen.Dim(Color(172, 220, 172), 1.0,
                       int(xoff + bx * sc), int(by * sc),
                       int((fw - 1) * sc), int(sc + 1));
        }
    }
}
