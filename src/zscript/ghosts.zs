// The E3 secret floor's Pac-Man ghosts (SpawnGhosts/T_Ghosts,
// WL_ACT2.C:1994-2020, 3207-3246).
//
// Two chase frames at 10 Wolf tics, dog speed (SPDDOG 1500), spawned
// straight into the chase table with FL_AMBUSH and dir east. They are
// never FL_SHOOTABLE - bullets pass through, which with the spawn-time
// killtotal++ makes 100% kills impossible on that floor, a quirk the
// original shipped with and this port keeps. First sighting doubles
// their speed (WL_STATE.C:1338) with no sight sound. Touch damage is
// MoveObj's too-close branch: 2 per Wolf tic of contact
// (WL_STATE.C:713, TakeDamage(tics*2)).

class WolfGhostTable
{
    // two-state loop: SPR per class, FRM A/B, think 6 = ChaseMove-only
    static const int FRM[]   = { 0, 1 };
    static const int TICS[]  = { 10, 10 };
    static const int THINK[] = { 6, 6 };
    static const int ACT[]   = { 0, 0 };
    static const int NEXT[]  = { 1, 0 };
}

class WolfGhost : WolfEnemySim abstract
{
    Default
    {
        -SHOOTABLE          // ghostobj never gets FL_SHOOTABLE
    }

    override int StateFrm(int i) { return WolfGhostTable.FRM[i]; }
    override int StateTics(int i) { return WolfGhostTable.TICS[i]; }
    override int StateThink(int i) { return WolfGhostTable.THINK[i]; }
    override int StateAction(int i) { return WolfGhostTable.ACT[i]; }
    override int StateNext(int i) { return WolfGhostTable.NEXT[i]; }
    override int StandState() { return 0; }
    override int PathState() { return 0; }
    override int ChaseState() { return 0; }
    override int PainState(bool alt) { return 0; }   // unreachable
    override int ShootState() { return 0; }          // unreachable
    override int DieState() { return 0; }            // unreachable
    override int BaseHP(int skill) { return 25; }    // starthitpoints row
    override int KillPoints() { return 0; }

    override void PostBeginPlay()
    {
        wolfSpeed = 1500;                // SPDDOG
        Super.PostBeginPlay();
        dir = 0;                         // east (SpawnGhosts)
        ambushFlag = true;               // FL_AMBUSH, unconditional
        SetState_(ChaseState());
    }

    // ghosts go faster when chasing the player; no sight sound
    override void FirstSighting()
    {
        wolfSpeed *= 2;
        attackMode = true;
    }

    override void OnPlayerContact()
    {
        PlayerPawn pm = TargetPM();
        if (pm != null)
            pm.DamageMobj(self, self, 4, 'Melee');  // tics*2, 2 Wolf tics
    }

    // sprite-name registration only - never entered (playbook 4)
    States
    {
    Reg:
        BLKY AB -1;
        PNKY AB -1;
        CLYD AB -1;
        INKY AB -1;
        Stop;
    }
}

class WolfGhostBlinky : WolfGhost
{
    override String StateSpr(int i) { return "BLKY"; }
}

class WolfGhostPinky : WolfGhost
{
    override String StateSpr(int i) { return "PNKY"; }
}

class WolfGhostClyde : WolfGhost
{
    override String StateSpr(int i) { return "CLYD"; }
}

class WolfGhostInky : WolfGhost
{
    override String StateSpr(int i) { return "INKY"; }
}
