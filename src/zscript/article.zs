// WolfArticle — the formatted-text screens (WL_TEXT.C).
//
// The end-of-episode articles are stored as text in the layout language
// PageLayout parses:
//
//   ^P              start of a page (must open the layout)
//   ^E              end of the layout
//   ^C<hex><hex>    set the font colour to a palette index
//   ^G<y>,<x>,<pic> draw a graphic and push the margins around it
//   ^L<x>,<y>       locate (y snaps to a text row)
//   ^B<y>,<x>,<w>,<h>  fill a bar in BACKCOLOR
//   ^;              comment to end of line
//   ^>              jump to x=160
//
// Word wrap is driven by per-row left/right margins, which the ^G handler
// rewrites for the rows a picture covers — that is what makes the text
// flow around the blaze picture on the first page.
class WolfArticle ui
{
    const BACKCOLOR   = 0x11;
    const FONTHEIGHT  = 10;
    const TOPMARGIN   = 16;
    const BOTTOMMARGIN = 32;
    const LEFTMARGIN  = 16;
    const RIGHTMARGIN = 16;
    const PICMARGIN   = 8;
    const TEXTROWS    = (200 - TOPMARGIN - BOTTOMMARGIN) / FONTHEIGHT;
    const SPACEWIDTH  = 7;
    const SCREENMID   = 160;

    String text;
    Array<int> pageStart;       // offset of each '^P'
    int pageNum;                // 0-based
    Font fnt;

    // layout state, reset per page
    Array<int> lMargin, rMargin;
    int px, py, rowOn;
    Color fontColor;
    bool layoutDone;

    bool Init(String lumpName)
    {
        int l = Wads.CheckNumForFullName(lumpName);
        if (l < 0)
            return false;
        text = Wads.ReadLump(l);
        fnt = Font.GetFont("wolfprop");
        if (fnt == null)
            return false;
        pageStart.Clear();
        for (int i = 0; i + 1 < text.Length(); i++)
        {
            if (text.ByteAt(i) == 94)               // '^'
            {
                int c = text.ByteAt(i + 1);
                if (c == 80 || c == 112)            // 'P'
                    pageStart.Push(i);
            }
        }
        pageNum = 0;
        return pageStart.Size() > 0;
    }

    int PageCount() { return pageStart.Size(); }

    // returns false once the last page has been passed
    bool NextPage()
    {
        pageNum++;
        return pageNum < pageStart.Size();
    }

    // BackPage (WL_TEXT.C:520) � the bottom bar promises "<> PAGE"
    void PrevPage()
    {
        if (pageNum > 0)
            pageNum--;
    }

    // ---- parsing helpers -------------------------------------------------

    int pos;                    // cursor while laying out

    void RipToEOL()
    {
        while (pos < text.Length() && text.ByteAt(pos) != 10)
            pos++;
        pos++;
    }

    int ParseNumber()
    {
        while (pos < text.Length())
        {
            int c = text.ByteAt(pos);
            if (c >= 48 && c <= 57)
                break;
            pos++;
        }
        int v = 0;
        while (pos < text.Length())
        {
            int c = text.ByteAt(pos);
            if (c < 48 || c > 57)
                break;
            v = v * 10 + (c - 48);
            pos++;
        }
        return v;
    }

    int ParseHexDigit()
    {
        int c = text.ByteAt(pos++);
        if (c >= 97) c -= 32;                       // to upper
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 65 && c <= 70) return c - 65 + 10;
        return 0;
    }

    // ---- drawing ---------------------------------------------------------

    void Bar(int x, int y, int w, int h, int palIndex)
    {
        // Ask the engine for the same rectangle DTA_320x200 draws into,
        // rather than reproducing its scaling by hand � the two disagree,
        // and the bar has to land exactly under the window frame.
        Vector2 rpos, rsize;
        [rpos, rsize] = Screen.VirtualToRealCoords((x, y), (w, h),
                                                   (320, 200), false, true);
        screen.Dim(WolfPal.Get(palIndex), 1.0, int(rpos.X), int(rpos.Y),
                   int(rsize.X + 1), int(rsize.Y + 1));
    }

    // Everything on this screen has to share ONE 320x200 transform, or the
    // background bar and the window frame land on different rectangles.
    void Pic(int x, int y, String lump)
    {
        screen.DrawTexture(TexMan.CheckForTexture(lump,
            TexMan.Type_MiscPatch), true, x, y,
            DTA_320x200, true);
    }

    void DrawWord(String word)
    {
        screen.DrawText(fnt, Font.CR_UNTRANSLATED, px, py, word,
                        DTA_320x200, true,
                        DTA_ColorOverlay, 0xFF000000 | fontColor);
    }

    void NewLine()
    {
        rowOn++;
        if (rowOn == TEXTROWS)
        {
            // overflowed the page: skip to the next page break
            layoutDone = true;
            while (pos + 1 < text.Length())
            {
                if (text.ByteAt(pos) == 94)
                {
                    int c = text.ByteAt(pos + 1);
                    if (c == 69 || c == 101 || c == 80 || c == 112)
                        return;
                }
                pos++;
            }
            return;
        }
        px = lMargin[rowOn];
        py += FONTHEIGHT;
    }

    void HandleCommand()
    {
        pos++;                                      // skip '^'
        int cmd = text.ByteAt(pos);
        if (cmd >= 97) cmd -= 32;                   // toupper
        pos++;
        if (cmd == 66)                              // B: bar
        {
            int by = ParseNumber(), bx = ParseNumber();
            int bw = ParseNumber(), bh = ParseNumber();
            Bar(bx, by, bw, bh, BACKCOLOR);
            RipToEOL();
        }
        else if (cmd == 59)                         // ';' comment
            RipToEOL();
        else if (cmd == 80 || cmd == 69)            // P / E: page done
        {
            layoutDone = true;
            pos--;                                  // back up to the '^'
        }
        else if (cmd == 67)                         // C: colour
        {
            int hi = ParseHexDigit();
            int lo = ParseHexDigit();
            fontColor = WolfPal.Get(hi * 16 + lo);
        }
        else if (cmd == 62)                         // '>' : centre tab
            px = 160;
        else if (cmd == 76)                         // L: locate
        {
            int ly = ParseNumber();
            rowOn = (ly - TOPMARGIN) / FONTHEIGHT;
            if (rowOn < 0) rowOn = 0;
            if (rowOn >= TEXTROWS) rowOn = TEXTROWS - 1;
            py = TOPMARGIN + rowOn * FONTHEIGHT;
            px = ParseNumber();
            RipToEOL();
        }
        else if (cmd == 71 || cmd == 84)            // G / T: graphic
        {
            int py2 = ParseNumber(), px2 = ParseNumber();
            int pic = ParseNumber();
            if (cmd == 84)
                ParseNumber();                      // ^T's delay
            RipToEOL();

            String lump = PicLump(pic);
            if (lump == "")
                return;
            TextureID t = TexMan.CheckForTexture(lump,
                                                 TexMan.Type_MiscPatch);
            Vector2 sz = TexMan.GetScaledSize(t);
            int gx = px2 & ~7;
            Pic(gx, py2, lump);

            // push the margins for every row the picture covers
            int picmid = gx + int(sz.X) / 2;
            int margin = picmid > SCREENMID ? gx - PICMARGIN
                                            : gx + int(sz.X) + PICMARGIN;
            int top = (py2 - TOPMARGIN) / FONTHEIGHT;
            if (top < 0) top = 0;
            int bottom = (py2 + int(sz.Y) - TOPMARGIN) / FONTHEIGHT;
            if (bottom >= TEXTROWS) bottom = TEXTROWS - 1;
            for (int i = top; i <= bottom; i++)
            {
                if (picmid > SCREENMID) rMargin[i] = margin;
                else                    lMargin[i] = margin;
            }
            if (px < lMargin[rowOn])
                px = lMargin[rowOn];
        }
    }

    void HandleWord()
    {
        String word = "";
        while (pos < text.Length() && text.ByteAt(pos) > 32)
        {
            word = word .. String.Format("%c", text.ByteAt(pos));
            pos++;
        }
        int wwidth = fnt.StringWidth(word);
        while (px + wwidth > rMargin[rowOn])
        {
            NewLine();
            if (layoutDone)
                return;
        }
        DrawWord(word);
        px += wwidth;
        while (pos < text.Length() && text.ByteAt(pos) == 32)
        {
            px += SPACEWIDTH;
            pos++;
        }
    }

    // PageLayout (WL_TEXT.C:410-500)
    void Draw()
    {
        if (pageNum >= pageStart.Size())
            return;

        Bar(0, 0, 320, 200, BACKCOLOR);
        Pic(0, 0, "H_TOPWIN");
        Pic(0, 8, "H_LEFTW");
        Pic(312, 8, "H_RIGHTW");
        Pic(8, 176, "H_BOTINF");

        lMargin.Resize(TEXTROWS);
        rMargin.Resize(TEXTROWS);
        for (int i = 0; i < TEXTROWS; i++)
        {
            lMargin[i] = LEFTMARGIN;
            rMargin[i] = 320 - RIGHTMARGIN;
        }
        px = LEFTMARGIN;
        py = TOPMARGIN;
        rowOn = 0;
        layoutDone = false;
        fontColor = WolfPal.Get(0);

        pos = pageStart[pageNum] + 2;               // past the "^P"
        RipToEOL();

        while (!layoutDone && pos < text.Length())
        {
            int ch = text.ByteAt(pos);
            if (ch == 94)                           // '^'
                HandleCommand();
            else if (ch == 9)                       // tab
            {
                px = (px + 8) & ~7;
                pos++;
            }
            else if (ch <= 32)
            {
                pos++;
                if (ch == 10)
                    NewLine();
            }
            else
                HandleWord();
        }

        // "pg N of M" in the bottom info bar
        fontColor = WolfPal.Get(0x4f);
        px = 213;
        py = 183;
        DrawWord(String.Format("pg %d of %d", pageNum + 1,
                               pageStart.Size()));
    }

    // The articles reference chunk numbers; only H_BLAZEPIC (5) is used by
    // the six end texts.
    static String PicLump(int chunk)
    {
        if (chunk == 5)  return "H_BLAZE";
        if (chunk == 4)  return "H_CASTLE";
        return "";
    }
}
