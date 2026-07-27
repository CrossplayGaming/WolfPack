// Pickups (GetBonus, WL_AGENT.C:656-770) + persistent game state.
//
// Charter: PICK-001..011 amounts and denial-at-caps, SCORE-001 extra life
// every 40,000 (EXTRAPOINTS), KILL-001..005 points. Pickup trigger =
// player center entering the tile: radius 10 + player 22 = the 32/axis
// box, matching the original's tile check.
//
// TODO(AdLib pass): all pickup sounds are AdLib-only in the source
// (HEALTH1SND, GETAMMOSND, BONUS1-4SND...) — silent until OPL synthesis.

class WolfGameState : StaticEventHandler
{
    int score;
    int lives;
    int nextExtra;
    int oldScore;       // score at floor entry (DEATH-004)
    bool deathRestart;
    bool skipPsyched;
    bool victoryFlag;
    bool initialized;

    // LevelRatios[8] (WL_INTER.C:424): the per-floor kill/secret/treasure
    // percentages and times that the episode-end Victory screen averages.
    // The original indexes this by mapon, so the secret floor (mapon 9)
    // writes past the end of the array; we clamp instead of reproducing
    // that out-of-bounds write.
    Array<int> lrKill, lrSecret, lrTreasure, lrTime;

    void RecordRatios(int floorNum, int kill, int secret, int treasure,
                      int levelSec)
    {
        int i = floorNum - 1;
        if (i < 0 || i > 7)
            return;
        if (lrKill.Size() < 8)
        {
            lrKill.Resize(8); lrSecret.Resize(8);
            lrTreasure.Resize(8); lrTime.Resize(8);
        }
        lrKill[i] = kill; lrSecret[i] = secret;
        lrTreasure[i] = treasure; lrTime[i] = levelSec;
        CVar dv = CVar.FindCVar("wolf_dbg_victory");
        if (dv != null && dv.GetInt() != 0)
            Console.Printf("WOLFDBG ratios: floor %d k=%d s=%d t=%d %ds",
                           floorNum, kill, secret, treasure, levelSec);
    }

    void ClearRatios()
    {
        lrKill.Resize(0); lrSecret.Resize(0);
        lrTreasure.Resize(0); lrTime.Resize(0);
        lrKill.Resize(8); lrSecret.Resize(8);
        lrTreasure.Resize(8); lrTime.Resize(8);
    }

    const EXTRAPOINTS = 40000;      // WL_DEF.H:72

    clearscope static WolfGameState Get()
    {
        return WolfGameState(StaticEventHandler.Find("WolfGameState"));
    }

    override void WorldLoaded(WorldEvent e)
    {
        if (!initialized)
        {
            initialized = true;
            score = 0;
            lives = 3;
            oldScore = 0;
            nextExtra = EXTRAPOINTS;
            ClearRatios();
        }
    }

    // MLI (CHEAT-001): M+L+I held together in-game. Raw key tracking is
    // ui-side; scans are learned from each key's first KeyDown since
    // KeyUp events carry no char.
    ui int scanM, scanL, scanI;
    ui bool downM, downL, downI, mliFired;

    override bool InputProcess(InputEvent ev)
    {
        if (ev.type == InputEvent.Type_KeyDown)
        {
            int c = ev.KeyChar;
            if (c >= 65 && c <= 90) c += 32;
            if (c == 109) { scanM = ev.KeyScan; downM = true; }
            else if (c == 108) { scanL = ev.KeyScan; downL = true; }
            else if (c == 105) { scanI = ev.KeyScan; downI = true; }

            if (downM && downL && downI && !mliFired
                && Level.MapName != "TITLEMAP"
                && Menu.GetCurrentMenu() == null)
            {
                mliFired = true;
                EventHandler.SendNetworkEvent("wolf_mli");
                // CHEAT-002, verbatim (FOREIGN.H:95-99)
                Menu.StartMessage("You now have 100% Health,
"
                    "99 Ammo and both Keys!

Note that you have "
                    "basically
eliminated your chances of
"
                    "getting a high score!", 1);
            }
        }
        else if (ev.type == InputEvent.Type_KeyUp)
        {
            if (ev.KeyScan == scanM) { downM = false; mliFired = false; }
            else if (ev.KeyScan == scanL) { downL = false; mliFired = false; }
            else if (ev.KeyScan == scanI) { downI = false; mliFired = false; }
        }
        return false;
    }

    // the menus are ui scope and cannot start a game; they send this
    override void NetworkProcess(ConsoleEvent e)
    {
        if (e.Name == "wolf_mli")
        {
            DoMLI();
            return;
        }
        if (e.Name == "wolf_cheat")
        {
            DoCheat(e.Args[0]);
            return;
        }
        if (e.Name == "wolf_newgame")
        {
            // reset only: the map change itself goes through the
            // engine's real new-game path (Menu.StartGameDirect), because
            // ChangeLevel from the titlemap drags title state along
            if (players[0].mo != null)       // shed any victory freeze
                players[0].cheats &= ~CF_TOTALLYFROZEN;
            initialized = false;             // fresh score/lives on load
            deathRestart = false;
            ClearRatios();
        }
    }

    int mliPenalty;     // CHEAT-001: +42000 Wolf tics = 600 s of par time

    // MLI (WL_PLAY.C:657-693): health 100, ammo 99, both keys, chaingun,
    // score ZEROED, ten-minute par penalty
    void DoMLI()
    {
        PlayerPawn pm = players[0].mo;
        if (pm == null)
            return;
        pm.health = 100; pm.player.health = 100;
        Inventory a = pm.FindInventory("WolfAmmo");
        if (a != null) a.Amount = 99;
        pm.GiveInventoryType("WolfGoldKey");
        pm.GiveInventoryType("WolfSilverKey");
        pm.GiveInventoryType("WolfChaingun");
        score = 0;
        mliPenalty += 600;
    }

    // the cheat menu's actions (D-001): ui sends, play executes
    void DoCheat(int id)
    {
        PlayerPawn pm = players[0].mo;
        if (pm == null)
            return;
        switch (id)
        {
        case 0: players[0].cheats ^= CF_GODMODE; break;
        case 1: players[0].cheats ^= CF_NOCLIP; break;
        case 2:
            pm.GiveInventoryType("WolfMachineGun");
            pm.GiveInventoryType("WolfChaingun");
            pm.GiveInventoryType("WolfGoldKey");
            pm.GiveInventoryType("WolfSilverKey");
            {
                Inventory a = pm.FindInventory("WolfAmmo");
                if (a != null) a.Amount = 99;
            }
            break;
        case 3: pm.health = 100; pm.player.health = 100; break;
        case 4: level.ExitLevel(0, false); break;
        }
    }

    override void WorldUnloaded(WorldEvent e)
    {
        if (deathRestart)
        {
            score = oldScore;       // DEATH-004: roll back to floor entry
            deathRestart = false;
        }
        else
            oldScore = score;       // banked on a completed floor

        // LevelRatios[mapon] (WL_INTER.C:852-855): the finished floor's
        // percentages feed the episode-end averages. Floors 1-8 only; the
        // boss floor shows Victory() and the secret floor is out of range.
        WolfLevel wl = WolfLevel.Get();
        if (wl != null && !deathRestart && wl.floorNum >= 1
            && wl.floorNum <= 8)
        {
            int kr = wl.killTotal > 0
                     ? wl.killCount * 100 / wl.killTotal : 0;
            int sr = wl.secretTotal > 0
                     ? wl.secretCount * 100 / wl.secretTotal : 0;
            int tr = wl.treasureTotal > 0
                     ? wl.treasureCount * 100 / wl.treasureTotal : 0;
            int sec = level.time / GameTicRate;
            if (sec > 99 * 60)
                sec = 99 * 60;
            RecordRatios(wl.floorNum, kr, sr, tr, sec);
        }
    }

    void GivePoints(int pts)        // WL_AGENT.C:520-530
    {
        score += pts;
        while (score >= nextExtra)
        {
            nextExtra += EXTRAPOINTS;
            lives++;
            if (players[0].mo != null)
                players[0].mo.A_StartSound("wolf/bonus1up", CHAN_AUTO);
        }
    }
}

class WolfGoldKey : Key {}
class WolfSilverKey : Key {}

class WolfPickup : Inventory abstract
{
    Default
    {
        +SPECIAL                // Inventory does NOT default this flag
        +NOGRAVITY
        Radius 10;              // + player 22 = the 32/axis center-in-tile box
        Height 64;
        Inventory.PickupMessage "";
    }

    virtual int BonusKind() { return 0; }

    // GetBonus kinds (order per statinfo classes)
    enum EBonus
    {
        BO_FIRSTAID = 1, BO_FOOD, BO_ALPO, BO_GIBS,
        BO_CLIP, BO_CLIP2, BO_25CLIP,
        BO_MACHINEGUN, BO_CHAINGUN,
        BO_CROSS, BO_CHALICE, BO_BIBLE, BO_CROWN, BO_FULLHEAL,
        BO_KEY1, BO_KEY2,
    }

    // engine pickup path: TryPickup returning false leaves the item in
    // the world (Wolf's denial-at-caps), true consumes it
    override bool TryPickup(in out Actor toucher)
    {
        if (toucher == null || toucher.player == null)
            return false;
        WolfGameState gs = WolfGameState.Get();
        WolfLevel wl = WolfLevel.Get();
        Inventory am = toucher.FindInventory("WolfAmmo");
        int ammo = am == null ? 0 : am.Amount;

        switch (BonusKind())
        {
        case BO_FIRSTAID:                       // PICK-004
            if (toucher.health >= 100) return false;
            toucher.GiveBody(25, 100);
            toucher.A_StartSound("wolf/health2", CHAN_ITEM);
            break;
        case BO_FOOD:                           // PICK-005
            if (toucher.health >= 100) return false;
            toucher.GiveBody(10, 100);
            toucher.A_StartSound("wolf/health1", CHAN_ITEM);
            break;
        case BO_ALPO:                           // PICK-006
            if (toucher.health >= 100) return false;
            toucher.GiveBody(4, 100);
            toucher.A_StartSound("wolf/health1", CHAN_ITEM);
            break;
        case BO_GIBS:                           // PICK-012: heal 1 at <=10 HP
            if (toucher.health > 10) return false;
            toucher.GiveBody(1, 100);
            toucher.A_StartSound("wolf/slurpie", CHAN_ITEM);
            break;
        case BO_CLIP:                           // PICK-001
            if (ammo >= 99) return false;
            GiveAmmo_(toucher, 8);
            toucher.A_StartSound("wolf/getammo", CHAN_ITEM);
            break;
        case BO_CLIP2:                          // PICK-002
            if (ammo >= 99) return false;
            GiveAmmo_(toucher, 4);
            toucher.A_StartSound("wolf/getammo", CHAN_ITEM);
            break;
        case BO_25CLIP:                         // PICK-003 (SoD)
            if (ammo >= 99) return false;
            GiveAmmo_(toucher, 25);
            toucher.A_StartSound("wolf/getammo", CHAN_ITEM);
            break;
        case BO_MACHINEGUN:
            GiveWeapon_(toucher, "WolfMachineGun");
            toucher.A_StartSound("wolf/getmachine", CHAN_ITEM);
            break;
        case BO_CHAINGUN:
            GiveWeapon_(toucher, "WolfChaingun");
            toucher.A_StartSound("wolf/getgatling", CHAN_ITEM);
            {
                WolfPlayer wp = WolfPlayer(toucher);
                if (wp != null)
                    wp.grinCount = 140;         // PICK-010 gatling grin
                wp.faceCount = 0;
            }
            break;
        case BO_CROSS:                          // PICK-008
            gs.GivePoints(100);
            if (wl != null) wl.treasureCount++;
            toucher.A_StartSound("wolf/bonus1", CHAN_ITEM);
            break;
        case BO_CHALICE:
            gs.GivePoints(500);
            if (wl != null) wl.treasureCount++;
            toucher.A_StartSound("wolf/bonus2", CHAN_ITEM);
            break;
        case BO_BIBLE:
            gs.GivePoints(1000);
            if (wl != null) wl.treasureCount++;
            toucher.A_StartSound("wolf/bonus3", CHAN_ITEM);
            break;
        case BO_CROWN:
            gs.GivePoints(5000);
            if (wl != null) wl.treasureCount++;
            toucher.A_StartSound("wolf/bonus4", CHAN_ITEM);
            break;
        case BO_FULLHEAL:                       // PICK-007
            toucher.GiveBody(99, 100);
            GiveAmmo_(toucher, 25);
            gs.lives++;
            if (wl != null) wl.treasureCount++;
            toucher.A_StartSound("wolf/bonus1up", CHAN_ITEM);
            break;
        case BO_KEY1:                           // PICK-011
            toucher.GiveInventoryType("WolfGoldKey");
            toucher.A_StartSound("wolf/getkey", CHAN_ITEM);
            break;
        case BO_KEY2:
            toucher.GiveInventoryType("WolfSilverKey");
            toucher.A_StartSound("wolf/getkey", CHAN_ITEM);
            break;
        default:
            return false;
        }
        // StartBonusFlash: NUMWHITESHIFTS * WHITETICS (FLASH-001)
        WolfPlayer wp = WolfPlayer(toucher);
        if (wp != null)
            wp.bonusCount = 18;
        GoAwayAndDie();
        return true;
    }

    static void GiveAmmo_(Actor toucher, int amount)
    {
        Inventory am = toucher.FindInventory("WolfAmmo");
        if (am == null)
        {
            toucher.GiveInventoryType("WolfAmmo");
            am = toucher.FindInventory("WolfAmmo");
            if (am == null) return;
            am.Amount = 0;
        }
        am.Amount = Min(99, am.Amount + amount);
        // auto-raise the knife if we were dry (original re-arms via ready)
        PlayerInfo p = toucher.player;
        if (p != null && p.ReadyWeapon is "WolfKnife"
            && toucher.FindInventory("WolfPistol") != null)
        {
            p.PendingWeapon = Weapon(toucher.FindInventory("WolfPistol"));
        }
    }

    // GiveWeapon (WL_AGENT.C:581-590): +6 ammo, upgrade if better
    static void GiveWeapon_(Actor toucher, class<Weapon> cls)
    {
        GiveAmmo_(toucher, 6);
        if (toucher.FindInventory(cls) == null)
            toucher.GiveInventoryType(cls);
        // bestweapon upgrade: switch to it (selection order encodes rank)
        Weapon w = Weapon(toucher.FindInventory(cls));
        PlayerInfo p = toucher.player;
        if (w != null && p != null &&
            (p.ReadyWeapon == null
             || w.SelectionOrder < p.ReadyWeapon.SelectionOrder))
        {
            p.PendingWeapon = w;
        }
    }
}
