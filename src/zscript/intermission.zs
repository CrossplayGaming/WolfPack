// WolfIntermission — the LevelCompleted tally, one-for-one (D-002).
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
        if (levelSec > 99 * 60)
            levelSec = 99 * 60;
        parSec = wbs.partime / GameTicRate;
        timeLeft = parSec > levelSec ? parSec - levelSec : 0;

        phase = PH_BONUS;
        counter = 0;
        target = timeLeft;
        bonus = 0;
        waitTics = 0;

    }

    override void StartMusic()
    {
        S_ChangeMusic("ENDLEVEL", 0, true);
    }

    override void Ticker()
    {
        Super.Ticker();
        breatheTics++;
        if (breatheTics >= 35)      // BJ_Breathe
        {
            breatheTics = 0;
            breatheFrame ^= 1;
        }
        if (phase == PH_DONE)
            return;
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

    override void Drawer()
    {
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
        WolfWrite(9, 14, "kill ratio");
        WolfWrite(5, 16, "secret ratio");
        WolfWrite(1, 18, "treasure ratio");

        WolfWrite(26, 10, String.Format("%02d:%02d",
                                        levelSec / 60, levelSec % 60));
        WolfWrite(26, 12, String.Format("%02d:%02d",
                                        parSec / 60, parSec % 60));

        // running bonus (during PH_BONUS it counts seconds x PAR_AMOUNT)
        int shownBonus = phase == PH_BONUS ? counter * PAR_AMOUNT : bonus;
        WriteRight(36, 7, String.Format("%d", shownBonus));

        WriteRight(37, 14, String.Format("%d", phase == PH_KILL ? counter
                : (phase > PH_KILL ? killRatio : 0)) .. "%");
        WriteRight(37, 16, String.Format("%d", phase == PH_SECRET ? counter
                : (phase > PH_SECRET ? secretRatio : 0)) .. "%");
        WriteRight(37, 18, String.Format("%d", phase == PH_TREASURE ? counter
                : (phase > PH_TREASURE ? treasureRatio : 0)) .. "%");
    }
}
