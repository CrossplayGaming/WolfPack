// DeathCam — the boss-death replay (A_StartDeathCam, WL_ACT2.C:3765-3868).
//
// Flow, exactly as the source stages it: the boss's LAST death frame calls
// A_StartDeathCam. First call -> set victoryflag, dissolve the view to
// grey, print "Let's see that again!", wait, then teleport the camera to
// where the player stood at the kill (gamestate.killx/killy), aim it at
// the corpse, back it off 0x14000 (stepping 0x1000) until the spot is
// clear, dissolve back in and put the boss into its deathcam state, which
// replays the death animation. That replay ends on the same frame, so the
// SECOND call is what finishes the level victorious.
class WolfDeathCam : StaticEventHandler
{
    // play side
    int phase;              // 0 idle, 1 fading out, 2 caption, 3 fading in
    int timer;
    Actor bossActor;
    bool camLocked;
    Vector3 camPos;
    double camAngle;

    // ui side
    ui int rndval, drawn;
    ui bool started;

    const FADE_TICS = 72;       // same LFSR pace as the death fizzle
    const CAPTION_TICS = 105;   // IN_UserInput(300) at 70Hz = ~4.3 s

    clearscope static WolfDeathCam Get()
    {
        return WolfDeathCam(StaticEventHandler.Find("WolfDeathCam"));
    }

    // returns true if the caller should stop (cam took over)
    bool Begin(Actor boss, Vector3 killPos)
    {
        WolfGameState gs = WolfGameState.Get();
        if (gs == null)
            return false;
        if (netgame)
        {
            // co-op (user decision): no DeathCam - the replay staging is
            // built around one watcher. Straight to the episode end.
            gs.victoryFlag = true;
            return false;
        }
        if (gs.victoryFlag)
            return false;                   // second call: caller exits
        gs.victoryFlag = true;
        bossActor = boss;

        // camera: stand where the player was, look at the boss, then back
        // off until the spot is clear
        PlayerPawn pm = players[0].mo;
        if (pm != null && boss != null)
        {
            // WL_ACT2.C:3808-3835: aim from the KILL position at the
            // boss, then back away from the boss along that line until
            // the spot is clear. CheckPosition tests the spot itself;
            // CheckMove tested the PATH from the player and could fail
            // everywhere, falling back into a wall (the Hitler clip).
            camAngle = VectorAngle(boss.pos.x - killPos.x,
                                   boss.pos.y - killPos.y);
            double dist = 0x14000 / 1024.0;         // 80 map units
            Vector2 want = killPos.xy;
            for (int i = 0; i < 48; i++)
            {
                Vector2 p = boss.pos.xy - (cos(camAngle) * dist,
                                           sin(camAngle) * dist);
                want = p;                           // keep the farthest
                if (pm.CheckPosition(p))
                    break;
                dist += 0x1000 / 1024.0;            // step out 4 units
            }
            camPos = (want.x, want.y, pm.pos.z);
        }
        phase = 1;
        timer = FADE_TICS;
        Level.SetFrozen(true);
        return true;
    }

    override void WorldTick()
    {
        // once the cam is placed, pin it every tic until the level ends
        if (camLocked)
        {
            PlayerPawn pl = players[0].mo;
            if (pl != null)
            {
                pl.Angle = camAngle;
                pl.vel = (0, 0, 0);
            }
        }
        if (phase == 0)
            return;
        timer--;
        if (timer > 0)
            return;

        if (phase == 1)                 // faded out: hold the caption
        {
            phase = 2;
            timer = CAPTION_TICS;
        }
        else if (phase == 2)            // reposition and replay
        {
            PlayerPawn pm = players[0].mo;
            if (pm != null)
            {
                pm.SetOrigin(camPos, false);
                pm.Angle = camAngle;
                pm.vel = (0, 0, 0);
                // NewState(player, &s_deathcam): a think-less state, so
                // the camera is LOCKED; victoryflag lowers the weapon.
                // The status bar stays - the original always draws it.
                pm.player.cheats |= CF_TOTALLYFROZEN;
                PSprite psp = pm.player.GetPSprite(PSP_WEAPON);
                if (psp != null)
                    psp.SetState(null);
                pm.player.ReadyWeapon = null;
                camLocked = true;
            }
            WolfEnemySim e = WolfEnemySim(bossActor);
            if (e != null)
                e.StartDeathCamReplay();
            Level.SetFrozen(false);
            phase = 3;
            timer = FADE_TICS;
        }
        else                            // faded back in: done
        {
            phase = 0;
        }
    }

    override void RenderOverlay(RenderEvent e)
    {
        if (phase == 0)
        {
            started = false;
            return;
        }
        int w = screen.GetWidth(), h = screen.GetHeight();
        int viewH = h;
        CVar sb = CVar.GetCVar("screenblocks", players[consoleplayer]);
        if (sb != null && sb.GetInt() < 11)
            viewH = int(h * 160.0 / 200.0);

        if (phase == 2)                 // fully grey + caption
        {
            screen.Dim(Color(0, 65, 65), 1.0, 0, 0, w, viewH);
            DrawCaption(w, viewH);
            return;
        }

        // phase 1 dissolves grey IN; phase 3 dissolves it back OUT (the
        // source's fizzlein), so the same coverage set is drawn inverted
        if (!started)
        {
            started = true;
            rndval = 1;
            drawn = 0;
            cover.Resize(320 * 200);
            for (int i = 0; i < 320 * 200; i++)
                cover[i] = false;
        }
        int want = (FADE_TICS - timer) * 1828;
        while (drawn < want)
        {
            int x, y;
            [x, y, rndval] = WolfFizzle.Step(rndval);
            drawn++;
            if (x < 320 && y >= 0 && y < 200)
                cover[y * 320 + x] = true;
            if (rndval == 1)
                break;
        }
        bool invert = (phase == 3);
        double sx = w / 320.0, sy = viewH / 200.0;
        for (int cy = 0; cy < 200; cy++)
        {
            int run = -1;
            for (int cx = 0; cx <= 320; cx++)
            {
                bool on = cx < 320 && (cover[cy * 320 + cx] != invert);
                if (on && run < 0)
                    run = cx;
                else if (!on && run >= 0)
                {
                    screen.Dim(Color(0, 65, 65), 1.0, int(run * sx),
                               int(cy * sy), int((cx - run) * sx + 1),
                               int(sy + 1));
                    run = -1;
                }
            }
        }
        if (phase == 1)
            DrawCaption(w, viewH);
    }

    ui Array<bool> cover;

    ui void DrawCaption(int w, int viewH)
    {
        // Write(0,7,STR_SEEAGAIN) — the L_ letter pics, same as the tally
        String text = "let's see that again!";
        double sc = screen.GetHeight() / 200.0;
        double xoff = (w - 320 * sc) / 2;
        double nx = 0, ny = 7 * 8;
        for (int i = 0; i < text.Length(); i++)
        {
            int c = text.ByteAt(i);
            String pic = "";
            int adv = 16;
            if (c == 33)      { pic = "L_EXCL"; adv = 8; }
            else if (c == 39) { pic = "L_APOS"; adv = 8; }
            else if (c == 32) { }
            else
            {
                if (c >= 97) c -= 32;
                if (c >= 65 && c <= 90)
                    pic = String.Format("L_%c", c);
            }
            if (pic != "")
            {
                // use each glyph's own size: '!' and the apostrophe are
                // 8 wide, and forcing 16 stretched them into blocks
                TextureID t = TexMan.CheckForTexture(pic,
                                                     TexMan.Type_MiscPatch);
                Vector2 tsz = TexMan.GetScaledSize(t);
                screen.DrawTexture(t, false, xoff + nx * sc, ny * sc,
                                   DTA_DestWidth, int(tsz.X * sc),
                                   DTA_DestHeight, int(tsz.Y * sc));
            }
            nx += adv;
        }
    }
}
