// Spear of Destiny bosses (WL_ACT2.C SPEAR blocks).
//
// Five bosses plus the Spectre, all riding the shared WolfEnemySim
// interpreter over generated state tables. What is genuinely new here:
//
//   T_Will      the shared boss chase used by Wilhelm, the Angel and
//               the Death Knight - CheckLine then US_RndT() < (tics<<3),
//               which is exactly BossChase(3) (WL_ACT2.C:1177)
//   T_UShoot    the Ubermutant's volley: T_Shoot plus 10 contact damage
//               when the player is within one tile (WL_ACT2.C:1351)
//   T_Launch    projectile spawn; the Death Knight fires TWO angled
//               rockets (its shoot2 state swings -4 angle units, the
//               other +4) and the Angel fires sparks (WL_ACT2.C)
//   A_Relaunch  the Angel's three-shot burst, then the tired recharge;
//               a coin flip returns to chase in between
//   A_Victory   killing the Angel of Death wins Spear outright
//   A_Dormant   the Spectre's wait loop: invisible until the player is
//               close and the surrounding tiles are clear
//
// Deaths: bosses give 5000 points and the four key-carriers drop the
// gold key (KillActor, WL_STATE.C); the Spectre gives 200 and no key.
// Speeds are ASSIGNED at first sighting, not multiplied.

class WolfSodBoss : WolfBoss abstract
{
    override int KillPoints() { return 5000; }
    // the Spear bosses guard the elevator: gold key on death
    override void DropItem_() { PlaceDrop("SodStatic20"); }
    override int ChaseSpeedMul() { return 1; }   // speed set on sighting
}

// ------------------------------------------------------- Trans Grosse
class WolfTrans : WolfSodBoss
{
    override int StateRot(int i) { return WolfTransTable.ROT[i]; }
    override String StateSpr(int i) { return WolfTransTable.SPR[i]; }
    override int StateFrm(int i) { return WolfTransTable.FRM[i]; }
    override int StateTics(int i) { return WolfTransTable.TICS[i]; }
    override int StateThink(int i) { return WolfTransTable.THINK[i]; }
    override int StateAction(int i) { return WolfTransTable.ACT[i]; }
    override int StateNext(int i) { return WolfTransTable.NEXT[i]; }
    override int StandState() { return WolfTransTable.TRANSSTAND; }
    override int PathState() { return WolfTransTable.TRANSSTAND; }
    override int ChaseState() { return WolfTransTable.TRANSCHASE1; }
    override int ShootState() { return WolfTransTable.TRANSSHOOT1; }
    override int DieState() { return WolfTransTable.TRANSDIE0; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 850, 950, 1050, 1200 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int SightSpeed() { return 1536; }
    override void SightSound() { A_StartSound("sod/transsight", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("sod/transdeath", CHAN_VOICE); }
    override String DeathSnd() { return "sod/transdeath"; }
    override void AttackSound() { A_StartSound("wolf/bossfire", CHAN_WEAPON); }
}

// --------------------------------------------------- Barnacle Wilhelm
class WolfWill : WolfSodBoss
{
    override int StateRot(int i) { return WolfWillTable.ROT[i]; }
    override String StateSpr(int i) { return WolfWillTable.SPR[i]; }
    override int StateFrm(int i) { return WolfWillTable.FRM[i]; }
    override int StateTics(int i) { return WolfWillTable.TICS[i]; }
    override int StateThink(int i) { return WolfWillTable.THINK[i]; }
    override int StateAction(int i) { return WolfWillTable.ACT[i]; }
    override int StateNext(int i) { return WolfWillTable.NEXT[i]; }
    override int StandState() { return WolfWillTable.WILLSTAND; }
    override int PathState() { return WolfWillTable.WILLSTAND; }
    override int ChaseState() { return WolfWillTable.WILLCHASE1; }
    override int ShootState() { return WolfWillTable.WILLSHOOT1; }
    override int DieState() { return WolfWillTable.WILLDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 950, 1050, 1150, 1300 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int SightSpeed() { return 2048; }
    override void SightSound() { A_StartSound("sod/willsight", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("sod/willdeath", CHAN_VOICE); }
    override String DeathSnd() { return "sod/willdeath"; }
    override void AttackSound() { A_StartSound("wolf/bossfire", CHAN_WEAPON); }
}

// --------------------------------------------------------- Ubermutant
class WolfUber : WolfSodBoss
{
    override int StateRot(int i) { return WolfUberTable.ROT[i]; }
    override String StateSpr(int i) { return WolfUberTable.SPR[i]; }
    override int StateFrm(int i) { return WolfUberTable.FRM[i]; }
    override int StateTics(int i) { return WolfUberTable.TICS[i]; }
    override int StateThink(int i) { return WolfUberTable.THINK[i]; }
    override int StateAction(int i) { return WolfUberTable.ACT[i]; }
    override int StateNext(int i) { return WolfUberTable.NEXT[i]; }
    override int StandState() { return WolfUberTable.UBERSTAND; }
    override int PathState() { return WolfUberTable.UBERSTAND; }
    override int ChaseState() { return WolfUberTable.UBERCHASE1; }
    override int ShootState() { return WolfUberTable.UBERSHOOT1; }
    override int DieState() { return WolfUberTable.UBERDIE0; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 1050, 1150, 1250, 1400 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int SightSpeed() { return 3000; }
    override void SightSound() {}            // the Ubermutant is silent
    override void DeathSound() { A_StartSound("sod/uberdeath", CHAN_VOICE); }
    override String DeathSnd() { return "sod/uberdeath"; }
    override void AttackSound() { A_StartSound("wolf/bossfire", CHAN_WEAPON); }
}

// -------------------------------------------------------- Death Knight
class WolfDeathKnight : WolfSodBoss
{
    override int StateRot(int i) { return WolfDeathTable.ROT[i]; }
    override String StateSpr(int i) { return WolfDeathTable.SPR[i]; }
    override int StateFrm(int i) { return WolfDeathTable.FRM[i]; }
    override int StateTics(int i) { return WolfDeathTable.TICS[i]; }
    override int StateThink(int i) { return WolfDeathTable.THINK[i]; }
    override int StateAction(int i) { return WolfDeathTable.ACT[i]; }
    override int StateNext(int i) { return WolfDeathTable.NEXT[i]; }
    override int StandState() { return WolfDeathTable.DEATHSTAND; }
    override int PathState() { return WolfDeathTable.DEATHSTAND; }
    override int ChaseState() { return WolfDeathTable.DEATHCHASE1; }
    override int ShootState() { return WolfDeathTable.DEATHSHOOT1; }
    override int DieState() { return WolfDeathTable.DEATHDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 1250, 1350, 1450, 1600 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int SightSpeed() { return 2048; }
    override void SightSound() { A_StartSound("sod/knightsight", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("sod/knightdeath", CHAN_VOICE); }
    override String DeathSnd() { return "sod/knightdeath"; }
    // the knight fires paired heat-seekers, angled by its shoot state
    override bool IsDeathKnight() { return true; }
}

// ------------------------------------------------------ Angel of Death
class WolfAngel : WolfSodBoss
{
    override int StateRot(int i) { return WolfAngelTable.ROT[i]; }
    override String StateSpr(int i) { return WolfAngelTable.SPR[i]; }
    override int StateFrm(int i) { return WolfAngelTable.FRM[i]; }
    override int StateTics(int i) { return WolfAngelTable.TICS[i]; }
    override int StateThink(int i) { return WolfAngelTable.THINK[i]; }
    override int StateAction(int i) { return WolfAngelTable.ACT[i]; }
    override int StateNext(int i) { return WolfAngelTable.NEXT[i]; }
    override int StandState() { return WolfAngelTable.ANGELSTAND; }
    override int PathState() { return WolfAngelTable.ANGELSTAND; }
    override int ChaseState() { return WolfAngelTable.ANGELCHASE1; }
    override int ShootState() { return WolfAngelTable.ANGELSHOOT1; }
    override int DieState() { return WolfAngelTable.ANGELDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 1450, 1550, 1650, 2000 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int SightSpeed() { return 1536; }
    override void SightSound() { A_StartSound("sod/angelsight", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("sod/angeldeath", CHAN_VOICE); }
    override String DeathSnd() { return "sod/angeldeath"; }
    override bool IsAngel() { return true; }
    // A_Relaunch's tired branch and the chase return both live in the
    // table; only the burst counter and the recharge sound are ours
    override int TiredState() { return WolfAngelTable.ANGELTIRED; }
}

// ------------------------------------------------------------ Spectre
class WolfSpectre : WolfEnemySim
{
    override int StateRot(int i) { return WolfSpectreTable.ROT[i]; }
    override String StateSpr(int i) { return WolfSpectreTable.SPR[i]; }
    override int StateFrm(int i) { return WolfSpectreTable.FRM[i]; }
    override int StateTics(int i) { return WolfSpectreTable.TICS[i]; }
    override int StateThink(int i) { return WolfSpectreTable.THINK[i]; }
    override int StateAction(int i) { return WolfSpectreTable.ACT[i]; }
    override int StateNext(int i) { return WolfSpectreTable.NEXT[i]; }
    override int StandState() { return WolfSpectreTable.SPECTREWAIT1; }
    override int PathState() { return WolfSpectreTable.SPECTREWAIT1; }
    override int ChaseState() { return WolfSpectreTable.SPECTRECHASE1; }
    override int PainState(bool alt) { return WolfSpectreTable.SPECTRECHASE1; }
    override int ShootState() { return WolfSpectreTable.SPECTRECHASE1; }
    override int DieState() { return WolfSpectreTable.SPECTREDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 5, 10, 15, 25 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int KillPoints() { return 200; }
    override void SightSound() { A_StartSound("sod/ghostsight", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("sod/ghostfade", CHAN_VOICE); }
    override String DeathSnd() { return "sod/ghostfade"; }

    override void PostBeginPlay()
    {
        wolfSpeed = 800;
        Super.PostBeginPlay();
        ambushFlag = true;              // FL_AMBUSH, as SpawnSpectre sets
        SetState_(StandState());
    }

    override void FirstSighting()
    {
        Super.FirstSighting();
        wolfSpeed = 800;                // assigned, not multiplied
    }

    // like the WL6 ghosts, the Spectre drains on contact rather than
    // shooting (MoveObj's too-close branch, WL_STATE.C:713)
    override void OnPlayerContact()
    {
        PlayerPawn pm = TargetPM();
        if (pm != null)
            pm.DamageMobj(self, self, 4, 'Melee');
    }
}

// ---- Spear projectiles ------------------------------------------------
// The Death Knight's heat-seeker uses the rocket's damage and explosion;
// the Angel's spark is a four-frame sprite with the rocket's damage roll
// (T_Projectile shares the damage path for both, WL_ACT2.C).

class WolfHeatSeeker : WolfProjectile
{
    override int ProjDamage(WolfLevel wl) { return (wl.RndT() >> 3) + 30; }
    override bool BoomsOnWall() { return true; }
    override int ProjFrames() { return 1; }
    States { Spawn: HMIS A -1; Stop; }
}

class WolfSpark : WolfProjectile
{
    override int ProjDamage(WolfLevel wl) { return (wl.RndT() >> 3) + 30; }
    override int ProjFrames() { return 4; }
    States { Spawn: SPRK ABCD 6; Loop; }
}
