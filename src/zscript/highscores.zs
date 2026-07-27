// WolfHighScores — DrawHighScores (WL_INTER.C:1030-1130).
//
// Seven entries, shipped pre-filled with id's own names exactly as the
// original does (ID_US_1.C:57-65). The level column prints "E<n>/L<n>"
// and both the level and score numbers use the font's FIXED-WIDTH digits
// at codepoints 129-138, not the proportional ones — that is the
// `*str + (129 - '0')` remap in the source, and it is why the columns
// line up.
class WolfHighScores
{
    const MAXSCORES = 7;
    const BORDCOLOR = 0x29;
    const STRIPE    = 0x2c;

    static void Draw()
    {
        Font fnt = Font.GetFont("wolfprop");
        if (fnt == null)
            return;

        WolfDraw.Bar(0, 0, 320, 200, BORDCOLOR);        // ClearMScreen
        DrawStripes(10);
        WolfDraw.Pic(48, 0, "HISCORES");
        WolfDraw.Pic(4 * 8, 68, "C_NAME");
        WolfDraw.Pic(20 * 8, 68, "C_LEVEL");
        WolfDraw.Pic(28 * 8, 68, "C_SCORE");

        Color fg = WolfPal.Get(15);
        for (int i = 0; i < MAXSCORES; i++)
        {
            int y = 76 + 16 * i;
            String nm, lvl, sc;
            int ep;
            [nm, ep, lvl, sc] = Entry(i);

            WolfDraw.Text(fnt, 4 * 8, y, nm, fg);

            // level column: right-justified on the completed-floor digits
            String fw = FixedWidth(lvl);
            int x = 22 * 8 - fnt.StringWidth(fw) - 6;
            WolfDraw.Text(fnt, x, y,
                          String.Format("E%d/L", ep + 1) .. fw, fg);

            // score column
            String fs = FixedWidth(sc);
            WolfDraw.Text(fnt, 34 * 8 - 8 - fnt.StringWidth(fs), y, fs, fg);
        }
    }

    static void DrawStripes(int y)
    {
        WolfDraw.Bar(0, y, 320, 24, 0);
        WolfDraw.Bar(0, y + 22, 320, 1, STRIPE);        // VWB_Hlin
    }

    // '0'-'9' -> 129-138, the font's fixed-width digit block
    static String FixedWidth(String digits)
    {
        String res = "";
        for (int i = 0; i < digits.Length(); i++)
        {
            int c = digits.ByteAt(i);
            if (c >= 48 && c <= 57)
                c = c - 48 + 129;
            res = res .. String.Format("%c", c);
        }
        return res;
    }

    // the shipped table (ID_US_1.C:57-65)
    static String, int, String, String Entry(int i)
    {
        static const String NAMES[] = {
            "id software-'92", "Adrian Carmack", "John Carmack",
            "Kevin Cloud", "Tom Hall", "John Romero", "Jay Wilbur" };
        if (i < 0 || i >= MAXSCORES)
            return "", 0, "1", "10000";
        return NAMES[i], 0, "1", "10000";
    }
}
