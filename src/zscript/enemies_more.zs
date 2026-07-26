// Officer, SS, and Mutant — same generated-table interpreter as the guard;
// only the per-class constants differ (HP table, chase multiplier, reaction
// time, points, drops, voices).

// ----------------------------------------------------------------------
// Officer — HP 50, chase x5 (fastest human), fixed 2-tic reaction,
// 400 points, drops a clip.
// ----------------------------------------------------------------------
class WolfOfficer : WolfEnemySim abstract
{
    override int StateRot(int i) { return WolfOfficerTable.ROT[i]; }
    override String StateSpr(int i) { return WolfOfficerTable.SPR[i]; }
    override int StateFrm(int i) { return WolfOfficerTable.FRM[i]; }
    override int StateTics(int i) { return WolfOfficerTable.TICS[i]; }
    override int StateThink(int i) { return WolfOfficerTable.THINK[i]; }
    override int StateAction(int i) { return WolfOfficerTable.ACT[i]; }
    override int StateNext(int i) { return WolfOfficerTable.NEXT[i]; }
    override int StandState() { return WolfOfficerTable.OFCSTAND; }
    override int PathState() { return WolfOfficerTable.OFCPATH1; }
    override int ChaseState() { return WolfOfficerTable.OFCCHASE1; }
    override int PainState(bool alt)
    {
        return alt ? WolfOfficerTable.OFCPAIN : WolfOfficerTable.OFCPAIN1;
    }
    override int ShootState() { return WolfOfficerTable.OFCSHOOT1; }
    override int DieState() { return WolfOfficerTable.OFCDIE1; }
    override int ChaseSpeedMul() { return 5; }              // SPEED-002
    override int BaseHP(int skill) { return 50; }
    override int KillPoints() { return 400; }               // KILL-002
    override int ReactionTics(WolfLevel wl) { return 2; }   // REACT-002
    override void SightSound() { A_StartSound("wolf/spion", CHAN_VOICE); }
    override void DeathSound()
    {
        if (!SecretScream())
            A_StartSound("wolf/neinsovas", CHAN_VOICE);
    }
    override void AttackSound() { A_StartSound("wolf/nazifire", CHAN_WEAPON); }
    override void DropItem_() { PlaceDrop("WolfStatic48"); }
}

class WolfOfficerStand : WolfOfficer
{
    override void PostBeginPlay() { wolfSpeed = 512; Super.PostBeginPlay(); }
}

class WolfOfficerPatrol : WolfOfficer
{
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
        InitPatrol();
    }
}

// ----------------------------------------------------------------------
// SS — HP 100, chase x4, burst fire, better shot (ECOMBAT-002),
// 500 points. Drops the machine gun while the player has nothing better.
// ----------------------------------------------------------------------
class WolfSS : WolfEnemySim abstract
{
    override int StateRot(int i) { return WolfSSTable.ROT[i]; }
    override String StateSpr(int i) { return WolfSSTable.SPR[i]; }
    override int StateFrm(int i) { return WolfSSTable.FRM[i]; }
    override int StateTics(int i) { return WolfSSTable.TICS[i]; }
    override int StateThink(int i) { return WolfSSTable.THINK[i]; }
    override int StateAction(int i) { return WolfSSTable.ACT[i]; }
    override int StateNext(int i) { return WolfSSTable.NEXT[i]; }
    override int StandState() { return WolfSSTable.SSSTAND; }
    override int PathState() { return WolfSSTable.SSPATH1; }
    override int ChaseState() { return WolfSSTable.SSCHASE1; }
    override int PainState(bool alt)
    {
        return alt ? WolfSSTable.SSPAIN : WolfSSTable.SSPAIN1;
    }
    override int ShootState() { return WolfSSTable.SSSHOOT1; }
    override int DieState() { return WolfSSTable.SSDIE1; }
    override int ChaseSpeedMul() { return 4; }              // SPEED-004
    override int BaseHP(int skill) { return 100; }
    override int KillPoints() { return 500; }               // KILL-003
    override int ReactionTics(WolfLevel wl) { return 1 + wl.RndT() / 6; }
    override bool BetterShot() { return true; }             // ECOMBAT-002
    override void SightSound() { A_StartSound("wolf/schutzad", CHAN_VOICE); }
    override void DeathSound()
    {
        if (!SecretScream())
            A_StartSound("wolf/leben", CHAN_VOICE);
    }
    override void AttackSound() { A_StartSound("wolf/ssfire", CHAN_WEAPON); }
    override void DropItem_()
    {
        // KILL-003: bestweapon < machinegun -> machine gun, else a clip
        PlayerPawn pm = players[0].mo;
        bool hasBetter = pm != null
            && (pm.FindInventory("WolfMachineGun") != null
                || pm.FindInventory("WolfChaingun") != null);
        PlaceDrop(hasBetter ? "WolfStatic48" : "WolfStatic27");
    }
}

class WolfSSStand : WolfSS
{
    override void PostBeginPlay() { wolfSpeed = 512; Super.PostBeginPlay(); }
}

class WolfSSPatrol : WolfSS
{
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
        InitPatrol();
    }
}

// ----------------------------------------------------------------------
// Mutant — HP by skill (45/55/55/65), chase x3, silent on sight,
// 700 points, fires twice per attack sequence.
// ----------------------------------------------------------------------
class WolfMutant : WolfEnemySim abstract
{
    override int StateRot(int i) { return WolfMutantTable.ROT[i]; }
    override String StateSpr(int i) { return WolfMutantTable.SPR[i]; }
    override int StateFrm(int i) { return WolfMutantTable.FRM[i]; }
    override int StateTics(int i) { return WolfMutantTable.TICS[i]; }
    override int StateThink(int i) { return WolfMutantTable.THINK[i]; }
    override int StateAction(int i) { return WolfMutantTable.ACT[i]; }
    override int StateNext(int i) { return WolfMutantTable.NEXT[i]; }
    override int StandState() { return WolfMutantTable.MUTSTAND; }
    override int PathState() { return WolfMutantTable.MUTPATH1; }
    override int ChaseState() { return WolfMutantTable.MUTCHASE1; }
    override int PainState(bool alt)
    {
        return alt ? WolfMutantTable.MUTPAIN : WolfMutantTable.MUTPAIN1;
    }
    override int ShootState() { return WolfMutantTable.MUTSHOOT1; }
    override int DieState() { return WolfMutantTable.MUTDIE1; }
    override int ChaseSpeedMul() { return 3; }              // SPEED-003
    override int BaseHP(int skill)
    {
        // starthitpoints[difficulty][en_mutant] (WL_ACT2.C:42-155)
        static const int HP[] = { 45, 55, 55, 65 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int KillPoints() { return 700; }               // KILL-005
    override int ReactionTics(WolfLevel wl) { return 1 + wl.RndT() / 6; }
    override void SightSound() {}          // silent (no FirstSighting sound)
    override void DeathSound()
    {
        if (!SecretScream())
            A_StartSound("wolf/ahhhg", CHAN_VOICE);
    }
    override void AttackSound() { A_StartSound("wolf/nazifire", CHAN_WEAPON); }
    override void DropItem_() { PlaceDrop("WolfStatic48"); }
}

class WolfMutantStand : WolfMutant
{
    override void PostBeginPlay() { wolfSpeed = 512; Super.PostBeginPlay(); }
}

class WolfMutantPatrol : WolfMutant
{
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
        InitPatrol();
    }
}
