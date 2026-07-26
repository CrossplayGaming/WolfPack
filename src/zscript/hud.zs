// WolfStatusBar — the original status bar, one-for-one (D-002).
//
// Layout from WL_AGENT.C (StatusDrawPic x*8, y+160; LatchNumber
// right-justified 8px digits):
//   level (2,16,2)  score (6,16,6)  lives (14,16,1)  face (17,4)
//   health (21,16,3)  ammo (27,16,2)  keys (30,4)/(30,20)  weapon (32,8)
//
// Face logic: FACE-001..004 — look-around on US_RndT-driven timer, pic =
// FACE1A + 3*((100-health)/16) + frame, dead FACE8A, gatling grin hook.
class WolfStatusBar : BaseStatusBar
{
    override void Init()
    {
        Super.Init();
        SetSize(40, 320, 200);
    }

    override void Draw(int state, double TicFrac)
    {
        Super.Draw(state, TicFrac);
        if (state == HUD_None)
            return;
        if (state == HUD_Fullscreen)
        {
            DrawMinimal();
            return;
        }
        BeginStatusBar();
        // 1120-wide bar (frame + bevel tiled outward) centered on 320
        DrawImage("STATBAR", (-400, 160), DI_ITEM_OFFSETS);

        // floor number (1-based within episode: levelnum 1..10 per ep)
        int floorNum = ((Level.levelnum - 1) % 10) + 1;
        DrawWolfNumber(floorNum, 2, 2);
        DrawWolfNumber(0, 6, 6);                    // score: stats pass
        DrawWolfNumber(3, 14, 1);                   // lives: stats pass
        int health = CPlayer.mo == null ? 0 : CPlayer.health;
        DrawWolfNumber(health, 21, 3);
        Inventory am = CPlayer.mo.FindInventory("WolfAmmo");
        DrawWolfNumber(am == null ? 0 : am.Amount, 27, 2);

        // face (timer state lives on the player, play scope)
        WolfPlayer wp = WolfPlayer(CPlayer.mo);
        int faceFrame = wp == null ? 0 : wp.faceFrame;
        String face;
        if (health <= 0)
            face = "FACE8A";
        else if (wp != null && wp.grinCount > 0)
            face = "FACEGATL";
        else
        {
            int band = (100 - health) / 16;
            band = Clamp(band, 0, 6);
            face = String.Format("FACE%d%c", band + 1, 65 + faceFrame);
        }
        DrawImage(face, (136, 164), DI_ITEM_OFFSETS);

        // keys (items pass will set these; NOKEY until then)
        DrawImage("NOKEY", (240, 164), DI_ITEM_OFFSETS);
        DrawImage("NOKEY", (240, 180), DI_ITEM_OFFSETS);

        // weapon icon
        String wico = "KNIFEP";
        Weapon w = CPlayer.ReadyWeapon;
        if (w is "WolfChaingun")        wico = "GATLINGP";
        else if (w is "WolfMachineGun") wico = "MGUNP";
        else if (w is "WolfPistol")     wico = "GUNP";
        DrawImage(wico, (256, 168), DI_ITEM_OFFSETS);
    }

    // Minimal HUD (fullscreen view): floating pickup sprites with N_-font
    // counts beneath — lives + health bottom-left, ammo bottom-right.
    void DrawMinimal()
    {
        BeginHUD();
        DrawHudItem("HUDLIFE", 3, 14, false);
        DrawHudItem("HUDMED",
                    CPlayer.mo == null ? 0 : CPlayer.health, 52, false);
        Inventory am = CPlayer.mo.FindInventory("WolfAmmo");
        DrawHudItem("HUDAMMO", am == null ? 0 : am.Amount, -14, true);
    }

    void DrawHudItem(String tex, int value, double x, bool fromRight)
    {
        TextureID t = TexMan.CheckForTexture(tex, TexMan.Type_Any);
        Vector2 sz = (24, 24);
        if (t.IsValid())
            sz = TexMan.GetScaledSize(t);
        int anchor = fromRight ? DI_SCREEN_RIGHT_BOTTOM : DI_SCREEN_LEFT_BOTTOM;
        double cx = fromRight ? x - sz.X / 2 : x + sz.X / 2;
        DrawImage(tex, (fromRight ? x - sz.X : x, -14 - sz.Y),
                  anchor | DI_ITEM_OFFSETS, 0.72);
        String s = String.Format("%d", Max(0, value));
        double tx = cx - s.Length() * 4.0;
        for (int i = 0; i < s.Length(); i++)
        {
            DrawImage(String.Format("N_%c", s.ByteAt(i)), (tx, -12),
                      anchor | DI_ITEM_OFFSETS);
            tx += 8;
        }
    }

    // LatchNumber: right-justified, 8px per digit, leading blanks
    void DrawWolfNumber(int value, int xcell, int digits)
    {
        String s = String.Format("%d", Max(0, value));
        if (s.Length() > digits)
            s = s.Mid(s.Length() - digits, digits);
        int x = xcell * 8;
        for (int i = 0; i < digits - s.Length(); i++)
        {
            DrawImage("N_BLANK", (x, 176), DI_ITEM_OFFSETS);
            x += 8;
        }
        for (int i = 0; i < s.Length(); i++)
        {
            DrawImage(String.Format("N_%c", s.ByteAt(i)), (x, 176),
                      DI_ITEM_OFFSETS);
            x += 8;
        }
    }
}
