// Player death (Died, WL_GAME.C:1114-1225) and the fizzle fade.
//
// Sequence: weapon taken away + PLAYERDEATHSND, the view rotates to face
// the killer at DEATHROTATE (2 angle units per Wolf tic), the view fills
// solid red (palette 4) through the fizzle dissolve, a short wait, then
// lives-- and the floor restarts with the pistol loadout and the score
// rolled back to its level-entry value.
//
// Charter: DEATH-001..005, FIZZ-001..004.

// The fizzle fade's 17-bit LFSR (ID_VH.C:495-540), reproduced exactly:
// seed 1; each step shifts the 32-bit pair right one and, on carry, XORs
// 0x0001 into the high word and 0x2000 into the low. y = (low 8 bits)-1,
// x = next 9 bits; out-of-range pairs are skipped; the run ends when the
// sequence returns to 1.
class WolfFizzle
{
    static int, int, int Step(int rndval)
    {
        int lo = rndval & 0xFFFF;
        int hi = (rndval >> 16) & 0xFFFF;
        int y = (lo & 0xFF) - 1;
        int x = ((lo >> 8) & 0xFF) | ((hi & 1) << 8);
        int carry = lo & 1;
        lo = (lo >> 1) | ((hi & 1) << 15);
        hi = hi >> 1;
        if (carry != 0)
        {
            hi ^= 0x0001;
            lo ^= 0x2000;
        }
        return x, y, (hi << 16) | lo;
    }
}

class WolfDeathHandler : StaticEventHandler
{
    // play side sets these; the overlay reads them
    bool active;
    int  startTic;

    // ui-side progress. DEC-005: the dissolve runs the real LFSR but
    // marks 4x4 cells rather than single pixels — 64000 per-pixel draw
    // calls per frame is not viable, and canvas textures abort this
    // engine build's texture manager. Same pseudorandom pattern and
    // timing, coarser grain.
    const CELL = 4;
    const GW = 320 / CELL;
    const GH = 200 / CELL;
    ui int rndval;
    ui int drawn;
    ui bool started;
    ui bool complete;
    ui Array<bool> cover;

    // Rate, not duration: pixperframe = 64000/70 = 914 LFSR steps per
    // 1/70s frame -> 1828 per engine tic. The fade ends when the LFSR
    // completes its full 131071-step period, i.e. 2.05 s (71.7 tics) —
    // NOT the 70 frames the call's parameter suggests (ID_VH.C:483-540).
    const STEPS_PER_TIC = 1828;

    clearscope static WolfDeathHandler Get()
    {
        return WolfDeathHandler(StaticEventHandler.Find("WolfDeathHandler"));
    }

    void Begin()                    // play scope
    {
        active = true;
        startTic = Level.maptime;
    }

    void Finish()                   // play scope
    {
        active = false;
    }

    override void RenderOverlay(RenderEvent e)
    {
        if (!active)
        {
            started = false;
            return;
        }
        int w = screen.GetWidth(), h = screen.GetHeight();
        // the source fizzles the VIEW only (viewwidth x viewheight), so
        // the status bar stays visible underneath
        CVar sb = CVar.GetCVar("screenblocks", players[consoleplayer]);
        if (sb != null && sb.GetInt() < 11)
            h = int(h * 160.0 / 200.0);
        if (!started)
        {
            started = true;
            rndval = 1;
            drawn = 0;
            complete = false;
            cover.Resize(GW * GH);
            for (int i = 0; i < GW * GH; i++)
                cover[i] = false;
        }

        // reveal up to the count this tic calls for, marking cells
        int elapsed = Level.maptime - startTic;
        int want = elapsed * STEPS_PER_TIC;
        while (!complete && drawn < want)
        {
            int x, y;
            [x, y, rndval] = WolfFizzle.Step(rndval);
            drawn++;
            if (x < 320 && y >= 0 && y < 200)
                cover[(y / CELL) * GW + (x / CELL)] = true;
            if (rndval == 1)
                complete = true;        // full period: screen covered
        }

        // draw revealed cells, merging horizontal runs
        double sx = w / double(GW), sy = h / double(GH);
        for (int cy = 0; cy < GH; cy++)
        {
            int run = -1;
            for (int cx = 0; cx <= GW; cx++)
            {
                bool on = cx < GW && cover[cy * GW + cx];
                if (on && run < 0)
                    run = cx;
                else if (!on && run >= 0)
                {
                    screen.Dim(Color(168, 0, 0), 1.0,
                               int(run * sx), int(cy * sy),
                               int((cx - run) * sx + 1), int(sy + 1));
                    run = -1;
                }
            }
        }
    }
}
