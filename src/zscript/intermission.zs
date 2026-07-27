// WolfIntermission â€” the LevelCompleted tally, one-for-one (D-002).
//
// Layout and sequence from WL_INTER.C:560-800. Text is drawn with the
// game's own L_*PIC letter graphics (Write(), WL_INTER.C:331-385): cells
// are 8px, letters/digits advance 16px, and '!' ':' apostrophe advance 8.
//
// Sequence: par-time bonus counts up (a beep every 500 pts), then the
// kill / secret / treasure ratios each count 0..N with a beep every 10;
// a 100% ratio adds PERCENT100AMT and plays the fanfare, 0% plays the
// no-bonus sting, anything else the normal end-bonus tone. A keypress
// accelerates, as in the original.
//
// Charter: SCORE-002 (par 500/s), SCORE-003 (100% = 10,000), TALLY-001/002.
class WolfIntermission : StatusScreen
{
    // sequence phases
    enum EPhase { PH_BONUS, PH_KILL, PH_SECRET, PH_TREASURE, PH_DONE };

    int phase;
    int counter;        // value currently displayed for the running phase
    int target;         // value the running phase counts to
    int bonus;          // running bonus total (shown on the BONUS line)
    int waitTics;

    int killRatio, secretRatio, treasureRatio;
    int timeLeft, levelSec, parSec;
    int floorNum;
    int breatheTics, breatheFrame;

    // Victory() (WL_INTER.C:170-300) replaces the tally on a boss floor:
    // no count-up, just the episode averages and a keypress to leave.
    bool victoryMode;
    int avgKill, avgSecret, avgTreasure, totalSec;

    // EndText (WL_TEXT.C:800): after Victory() the episode's story article
    // plays, page by page, before the game returns to the title.
    WolfArticle article;
    bool inArticle;

    const PAR_AMOUNT = 500;         // WL_INTER.C:432
    const PERCENT100AMT = 10000;    // WL_INTER.C:433

    override void Start(wbstartstruct wbstartstruct)
    {
        Super.Start(wbstartstruct);
        WolfLevel wl = WolfLevel.Get();
        floorNum = wl == null ? 1 : wl.floorNum;

        killRatio = secretRatio = treasureRatio = 0;
        if (wl != null)
        {
            if (wl.killTotal > 0)
                killRatio = wl.killCount * 100 / wl.killTotal;
            if (wl.secretTotal > 0)
                secretRatio = wl.secretCount * 100 / wl.secretTotal;
            if (wl.treasureTotal > 0)
                treasureRatio = wl.treasureCount * 100 / wl.treasureTotal;
        }

        // TALLY-001: level time in seconds, capped at 99 minutes; par
        // comes from MAPINFO (generated from the extracted par table).
        levelSec = Plrs[me].stime / GameTicRate;
        WolfGameState pgs = WolfGameState.Get();
        if (pgs != null)
            levelSec += pgs.mliPenalty;      // CHEAT-001
        if (levelSec > 99 * 60)
            levelSec = 99 * 60;
        parSec = wbs.partime / GameTicRate;
        timeLeft = parSec > levelSec ? parSec - levelSec : 0;

        // the boss floor ends the episode (ex_victorious), so it shows
        // Victory() instead of the tally and records nothing
        victoryMode = (floorNum == 9);

        // (the per-floor ratios themselves are recorded play-side, in
        // WolfGameState.WorldUnloaded — a ui screen may read play data but
        // not write it)
        WolfGameState gs = WolfGameState.Get();
        if (gs != null && victoryMode)
        {
            int kr, sr, tr, sec;
            for (int i = 0; i < 8 && i < int(gs.lrKill.Size()); i++)
            {
                kr += gs.lrKill[i];     sr += gs.lrSecret[i];
                tr += gs.lrTreasure[i]; sec += gs.lrTime[i];
            }
            avgKill = kr / 8; avgSecret = sr / 8; avgTreasure = tr / 8;
            totalSec = sec;
            if (totalSec / 60 > 99)
                totalSec = 99 * 60 + 99;
        }

        phase = victoryMode ? PH_DONE : PH_BONUS;
        counter = 0;
        target = timeLeft;
        bonus = 0;
        waitTics = 0;

    }

    override void StartMusic()
    {
        S_ChangeMusic(victoryMode ? "URAHERO" : "ENDLEVEL", 0, true);
    }

    // Input: any key accelerates the count-up, and once the tally has
    // finished any key leaves the screen (IN_Ack at the end of
    // LevelCompleted). Without this the screen had no way out.
    override bool OnEvent(InputEvent ev)
    {
        if (ev.type == InputEvent.Type_KeyDown)
        {
            if (victoryMode && phase == PH_DONE)
            {
                int k = ev.KeyScan;
                if (inArticle && article != null)
                {
                    if (k == InputEvent.Key_LeftArrow)
                    {
                        article.PrevPage();
                        return true;
                    }
                    if (k == InputEvent.Key_Escape)
                    {
                        End();
                        return true;
                    }
                }
                AdvanceVictory();
                return true;
            }
            if (phase == PH_DONE)
                End();              // -> LeavingIntermission
            else
                acceleratestage = 1;
            return true;
        }
        return false;
    }

    // Victory screen -> article pages -> out
    void AdvanceVictory()
    {
        if (!inArticle)
        {
            article = new("WolfArticle");
            int ep = level.levelnum / 10 + 1;
            if (article.Init(String.Format("ENDART%d.txt", ep)))
            {
                inArticle = true;
                return;
            }
            article = null;
        }
        else if (article.NextPage())
            return;
        End();
    }

    // NOT Super.Ticker(): the base state machine advances the screen on
    // its own schedule, which would cut the tally short.
    override void Ticker()
    {
        bcnt++;
        if (bcnt == 1)
            StartMusic();
        breatheTics += 2;           // Wolf tics
        if (breatheTics >= 35)      // BJ_Breathe: max = 35 (0.5 s)
        {
            breatheTics = 0;
            breatheFrame ^= 1;
        }
        if (phase == PH_DONE)
        {
            // self-test: page through the ending without a keyboard
            CVar dv = CVar.GetCVar("wolf_dbg_victory",
                                   players[consoleplayer]);
            if (victoryMode && dv != null && dv.GetInt() >= 2
                && (bcnt % 70) == 0)
                AdvanceVictory();
            return;                 // otherwise wait for a key (OnEvent)
        }
        if (waitTics > 0)
        {
            waitTics--;
            return;
        }

        // a keypress accelerates: finish the current phase instantly
        bool rush = acceleratestage != 0;
        int step = rush ? 1000000 : 1;

        if (counter < target)
        {
            counter = min(target, counter + step);
            if (phase == PH_BONUS)
            {
                // beep every PAR_AMOUNT/10 counted seconds
                if (!rush)
                    PlaySound("wolf/endbonus1");
            }
            else if (!rush && (counter % 10) == 0)
            {
                PlaySound("wolf/endbonus1");
            }
            return;
        }

        // phase complete: award and advance
        acceleratestage = 0;
        if (phase == PH_BONUS)
        {
            bonus += timeLeft * PAR_AMOUNT;
            if (timeLeft > 0)
                PlaySound("wolf/endbonus2");
        }
        else
        {
            int ratio = counter;
            if (ratio == 100)
            {
                bonus += PERCENT100AMT;         // SCORE-003
                PlaySound("wolf/percent100");
            }
            else if (ratio == 0)
                PlaySound("wolf/nobonus");
            else
                PlaySound("wolf/endbonus2");
        }

        phase++;
        counter = 0;
        waitTics = 20;
        if (phase == PH_KILL)         target = killRatio;
        else if (phase == PH_SECRET)  target = secretRatio;
        else if (phase == PH_TREASURE) target = treasureRatio;
        else
        {
            // (the score itself was banked at level exit, in play scope)
            phase = PH_DONE;
        }
    }

    // Write() (WL_INTER.C:331-385): L_ letter pics on an 8px cell grid.
    // Letters/digits are 16 wide; '!' ':' and apostrophe are 8.
    void WolfWrite(int cx, int cy, String text)
    {
        int nx = cx * 8, ny = cy * 8;
        int ox = nx;
        for (int i = 0; i < text.Length(); i++)
        {
            int c = text.ByteAt(i);
            if (c == 10)                    // '\\n'
            {
                nx = ox;
                ny += 16;
                continue;
            }
            String pic = "";
            int adv = 16;
            if (c == 33)      { pic = "L_EXCL"; adv = 8; }
            else if (c == 39) { pic = "L_APOS";    adv = 8; }
            else if (c == 58) { pic = "L_COLON";   adv = 8; }
            else if (c == 37) { pic = "L_PCT"; }
            else if (c == 32) { }
            else if (c >= 48 && c <= 57)
                pic = String.Format("L_NUM%d", c - 48);
            else
            {
                if (c >= 97) c -= 32;       // lower -> upper
                if (c >= 65 && c <= 90)
                    pic = String.Format("L_%c", c);
            }
            if (pic != "")
                screen.DrawTexture(TexMan.CheckForTexture(pic,
                    TexMan.Type_MiscPatch), true, nx, ny,
                    DTA_320x200, true);
            nx += adv;
        }
    }

    void WriteRight(int cellRight, int cy, String text)
    {
        // right-justified like the source: x = edge - len*2 cells
        WolfWrite(cellRight - text.Length() * 2, cy, text);
    }

    // VWB_DrawPic takes pixel coordinates, not the Write() cell grid
    void DrawPicPx(double x, double y, String pic)
    {
        screen.DrawTexture(TexMan.CheckForTexture(pic,
            TexMan.Type_MiscPatch), true, x, y, DTA_320x200, true);
    }

    void DrawVictory()
    {
        screen.Dim(Color(0, 65, 65), 1.0, 0, 0, screen.GetWidth(),
                   screen.GetHeight());
        DrawPicPx(8, 4, "L_BJWINS");

        WolfWrite(18, 2, "you win!");
        WolfWrite(14, 6, "total time");       // TIMEX, TIMEY-2
        WolfWrite(12, 12, "averages");        // RATIOY-2
        WolfWrite(14, 14, "kill    %");       // RATIOX+8, RATIOY
        WolfWrite(10, 16, "secret    %");     // RATIOX+4
        WolfWrite(6, 18, "treasure    %");    // RATIOX

        // total time: L_NUM pics stepped 2 cells apart with a ':' between
        int mn = totalSec / 60, sc = totalSec % 60;
        double i = 14 * 8 + 1;
        DrawPicPx(i, 64, String.Format("L_NUM%d", mn / 10));   i += 16;
        DrawPicPx(i, 64, String.Format("L_NUM%d", mn % 10));   i += 16;
        WolfWrite(int(i) / 8, 8, ":");                         i += 8;
        DrawPicPx(i, 64, String.Format("L_NUM%d", sc / 10));   i += 16;
        DrawPicPx(i, 64, String.Format("L_NUM%d", sc % 10));

        // ratios right-justified at RATIOX+24
        WriteRight(30, 14, String.Format("%d", avgKill));
        WriteRight(30, 16, String.Format("%d", avgSecret));
        WriteRight(30, 18, String.Format("%d", avgTreasure));
    }

    override void Drawer()
    {
        if (victoryMode)
        {
            if (inArticle && article != null)
            {
                // same letterbox treatment as Read This!: wood backdrop
                // (the parchment frame art clashes on stone), bevel ring
                WolfDraw.Backdrop("WALL022");
                double bpx = WolfDraw.Px();
                double bh = screen.GetHeight() - 32 * bpx;
                double bw = bh * (4.0 / 3.0);
                double bx = (screen.GetWidth() - bw) / 2;
                WolfDraw.BevelRing(bx, 16 * bpx, bw, bh);
                article.SetRect(bx, 16 * bpx, bw, bh);
                article.Draw();
            }
            else
                DrawVictory();
            return;
        }
        // VWB_Bar(0,0,320,200-STATUSLINES,127): palette 127 = (0,65,65)
        screen.Dim(Color(0, 65, 65), 1.0, 0, 0, screen.GetWidth(),
                   screen.GetHeight());
        screen.DrawTexture(TexMan.CheckForTexture(
            breatheFrame == 0 ? "L_GUY" : "L_GUY2", TexMan.Type_MiscPatch),
            true, 0, 16, DTA_320x200, true);

        WolfWrite(14, 2, "floor\ncompleted");
        WolfWrite(26, 2, String.Format("%d", floorNum));
        WolfWrite(14, 7, "bonus");
        WolfWrite(16, 10, "time");
        WolfWrite(16, 12, "par");
        WolfWrite(9, 14, "kill ratio    %");
        WolfWrite(5, 16, "secret ratio    %");
        WolfWrite(1, 18, "treasure ratio    %");

        WolfWrite(26, 10, String.Format("%02d:%02d",
                                        levelSec / 60, levelSec % 60));
        WolfWrite(26, 12, String.Format("%02d:%02d",
                                        parSec / 60, parSec % 60));

        // running bonus (during PH_BONUS it counts seconds x PAR_AMOUNT)
        int shownBonus = phase == PH_BONUS ? counter * PAR_AMOUNT : bonus;
        WriteRight(36, 7, String.Format("%d", shownBonus));

        WriteRight(37, 14, String.Format("%d", phase == PH_KILL ? counter
                : (phase > PH_KILL ? killRatio : 0)));
        WriteRight(37, 16, String.Format("%d", phase == PH_SECRET ? counter
                : (phase > PH_SECRET ? secretRatio : 0)));
        WriteRight(37, 18, String.Format("%d", phase == PH_TREASURE ? counter
                : (phase > PH_TREASURE ? treasureRatio : 0)));
    }
}
