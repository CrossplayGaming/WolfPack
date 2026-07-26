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
    bool initialized;

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
            nextExtra = EXTRAPOINTS;
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
