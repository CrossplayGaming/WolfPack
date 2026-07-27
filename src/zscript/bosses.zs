// Bosses and their projectiles.
//
// Shared traits (checklist section 2): bosses are deaf until SEEN
// (FL_AMBUSH on spawn, so noise never wakes them), have NO pain states —
// their tables contain none, so DamageActor cannot flinch them — and
// several drop keys or trigger the DeathCam. Chase speeds and HP come
// from the charter (SPEED-006..008, the starthitpoints table).
//
// The projectile bosses (Schabbs, Gift, Fat, Fake) use T_Schabb/T_Gift/
// T_Fat/T_Fake: identical to T_Chase except the attack roll is a flat
// US_RndT() < (tics<<N) rather than the distance formula.

class WolfBoss : WolfEnemySim abstract
{
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        // SpawnBoss: FL_AMBUSH -> sight only, never noise
        ambushFlag = true;
    }
    override void LazyInit(WolfLevel wl)
    {
        Super.LazyInit(wl);
        ambushFlag = true;          // keep it: bosses are always deaf
    }
    // no pain states exist in boss tables; make that explicit
    override int PainState(bool alt) { return stateIdx; }
    override int ReactionTics(WolfLevel wl) { return 1; }   // REACT-006
    override int KillPoints() { return 5000; }              // BOSS-001
    override bool BetterShot() { return true; }             // ECOMBAT-002
}

// ---------------------------------------------------------------- Hans
class WolfHans : WolfBoss
{
    override int StateRot(int i) { return WolfHansTable.ROT[i]; }
    override String StateSpr(int i) { return WolfHansTable.SPR[i]; }
    override int StateFrm(int i) { return WolfHansTable.FRM[i]; }
    override int StateTics(int i) { return WolfHansTable.TICS[i]; }
    override int StateThink(int i) { return WolfHansTable.THINK[i]; }
    override int StateAction(int i) { return WolfHansTable.ACT[i]; }
    override int StateNext(int i) { return WolfHansTable.NEXT[i]; }
    override int StandState() { return WolfHansTable.BOSSSTAND; }
    override int PathState() { return WolfHansTable.BOSSSTAND; }
    override int ChaseState() { return WolfHansTable.BOSSCHASE1; }
    override int ShootState() { return WolfHansTable.BOSSSHOOT1; }
    override int DieState() { return WolfHansTable.BOSSDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 850, 950, 1050, 1200 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int ChaseSpeedMul() { return 1; }      // SPEED-006: set below
    override void PostBeginPlay()
    {
        wolfSpeed = 512 * 3;        // SPDPATROL*3, assigned outright
        Super.PostBeginPlay();
        dir = 6;                    // MAP-018: Hans faces south
    }
    override void SightSound() { A_StartSound("wolf/gutentag", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/mutti", CHAN_VOICE); }
    override void AttackSound() { A_StartSound("wolf/bossfire", CHAN_WEAPON); }
    override void DropItem_() { PlaceDrop("WolfStatic20"); }   // BOSS-002
}

// -------------------------------------------------------------- Gretel
class WolfGretel : WolfBoss
{
    override int StateRot(int i) { return WolfGretelTable.ROT[i]; }
    override String StateSpr(int i) { return WolfGretelTable.SPR[i]; }
    override int StateFrm(int i) { return WolfGretelTable.FRM[i]; }
    override int StateTics(int i) { return WolfGretelTable.TICS[i]; }
    override int StateThink(int i) { return WolfGretelTable.THINK[i]; }
    override int StateAction(int i) { return WolfGretelTable.ACT[i]; }
    override int StateNext(int i) { return WolfGretelTable.NEXT[i]; }
    override int StandState() { return WolfGretelTable.GRETELSTAND; }
    override int PathState() { return WolfGretelTable.GRETELSTAND; }
    override int ChaseState() { return WolfGretelTable.GRETELCHASE1; }
    override int ShootState() { return WolfGretelTable.GRETELSHOOT1; }
    override int DieState() { return WolfGretelTable.GRETELDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 850, 950, 1050, 1200 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
        dir = 2;                    // MAP-018: Gretel faces north
    }
    override int ChaseSpeedMul() { return 3; }
    override void SightSound() { A_StartSound("wolf/kein", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/mutti", CHAN_VOICE); }
    override void AttackSound() { A_StartSound("wolf/bossfire", CHAN_WEAPON); }
    override void DropItem_() { PlaceDrop("WolfStatic20"); }
}

// ------------------------------------------------------------- Schabbs
class WolfSchabbs : WolfBoss
{
    override int StateRot(int i) { return WolfSchabbsTable.ROT[i]; }
    override String StateSpr(int i) { return WolfSchabbsTable.SPR[i]; }
    override int StateFrm(int i) { return WolfSchabbsTable.FRM[i]; }
    override int StateTics(int i) { return WolfSchabbsTable.TICS[i]; }
    override int StateThink(int i) { return WolfSchabbsTable.THINK[i]; }
    override int StateAction(int i) { return WolfSchabbsTable.ACT[i]; }
    override int StateNext(int i) { return WolfSchabbsTable.NEXT[i]; }
    override int StandState() { return WolfSchabbsTable.SCHABBSTAND; }
    override int PathState() { return WolfSchabbsTable.SCHABBSTAND; }
    override int ChaseState() { return WolfSchabbsTable.SCHABBCHASE1; }
    override int ShootState() { return WolfSchabbsTable.SCHABBSHOOT1; }
    override int DieState() { return WolfSchabbsTable.SCHABBDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 850, 950, 1550, 2400 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
    }
    override int ChaseSpeedMul() { return 3; }
    override bool DeathCamBoss() { return true; }       // BOSS-003
    override void SightSound() { A_StartSound("wolf/schabbsha", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/meingott", CHAN_VOICE); }
}

// ---------------------------------------------------------------- Gift
class WolfGift : WolfBoss
{
    override int StateRot(int i) { return WolfGiftTable.ROT[i]; }
    override String StateSpr(int i) { return WolfGiftTable.SPR[i]; }
    override int StateFrm(int i) { return WolfGiftTable.FRM[i]; }
    override int StateTics(int i) { return WolfGiftTable.TICS[i]; }
    override int StateThink(int i) { return WolfGiftTable.THINK[i]; }
    override int StateAction(int i) { return WolfGiftTable.ACT[i]; }
    override int StateNext(int i) { return WolfGiftTable.NEXT[i]; }
    override int StandState() { return WolfGiftTable.GIFTSTAND; }
    override int PathState() { return WolfGiftTable.GIFTSTAND; }
    override int ChaseState() { return WolfGiftTable.GIFTCHASE1; }
    override int ShootState() { return WolfGiftTable.GIFTSHOOT1; }
    override int DieState() { return WolfGiftTable.GIFTDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 850, 950, 1050, 1200 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
    }
    override int ChaseSpeedMul() { return 3; }
    override bool DeathCamBoss() { return true; }
    override void SightSound() { A_StartSound("wolf/eine", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/donner", CHAN_VOICE); }
}

// ----------------------------------------------------------------- Fat
class WolfFat : WolfBoss
{
    override int StateRot(int i) { return WolfFatTable.ROT[i]; }
    override String StateSpr(int i) { return WolfFatTable.SPR[i]; }
    override int StateFrm(int i) { return WolfFatTable.FRM[i]; }
    override int StateTics(int i) { return WolfFatTable.TICS[i]; }
    override int StateThink(int i) { return WolfFatTable.THINK[i]; }
    override int StateAction(int i) { return WolfFatTable.ACT[i]; }
    override int StateNext(int i) { return WolfFatTable.NEXT[i]; }
    override int StandState() { return WolfFatTable.FATSTAND; }
    override int PathState() { return WolfFatTable.FATSTAND; }
    override int ChaseState() { return WolfFatTable.FATCHASE1; }
    override int ShootState() { return WolfFatTable.FATSHOOT1; }
    override int DieState() { return WolfFatTable.FATDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 850, 950, 1050, 1200 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
    }
    override int ChaseSpeedMul() { return 3; }
    override bool DeathCamBoss() { return true; }
    override void SightSound() { A_StartSound("wolf/erlauben", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/mein", CHAN_VOICE); }
}

// --------------------------------------------------------- Fake Hitler
class WolfFakeHitler : WolfBoss
{
    override int StateRot(int i) { return WolfFakeTable.ROT[i]; }
    override String StateSpr(int i) { return WolfFakeTable.SPR[i]; }
    override int StateFrm(int i) { return WolfFakeTable.FRM[i]; }
    override int StateTics(int i) { return WolfFakeTable.TICS[i]; }
    override int StateThink(int i) { return WolfFakeTable.THINK[i]; }
    override int StateAction(int i) { return WolfFakeTable.ACT[i]; }
    override int StateNext(int i) { return WolfFakeTable.NEXT[i]; }
    override int StandState() { return WolfFakeTable.FAKESTAND; }
    override int PathState() { return WolfFakeTable.FAKESTAND; }
    override int ChaseState() { return WolfFakeTable.FAKECHASE1; }
    override int ShootState() { return WolfFakeTable.FAKESHOOT1; }
    override int DieState() { return WolfFakeTable.FAKEDIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 200, 300, 400, 500 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override int KillPoints() { return 2000; }      // BOSS-001 exception
    override bool CardinalDiag() { return true; }   // CHASE-003: no doors
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
    }
    override int ChaseSpeedMul() { return 3; }
    override void SightSound() { A_StartSound("wolf/tothund", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/hitlerha", CHAN_VOICE); }
}

// -------------------------------------------------------- Mecha Hitler
class WolfMechaHitler : WolfBoss
{
    override int StateRot(int i) { return WolfMechaTable.ROT[i]; }
    override String StateSpr(int i) { return WolfMechaTable.SPR[i]; }
    override int StateFrm(int i) { return WolfMechaTable.FRM[i]; }
    override int StateTics(int i) { return WolfMechaTable.TICS[i]; }
    override int StateThink(int i) { return WolfMechaTable.THINK[i]; }
    override int StateAction(int i) { return WolfMechaTable.ACT[i]; }
    override int StateNext(int i) { return WolfMechaTable.NEXT[i]; }
    override int StandState() { return WolfMechaTable.MECHASTAND; }
    override int PathState() { return WolfMechaTable.MECHASTAND; }
    override int ChaseState() { return WolfMechaTable.MECHACHASE1; }
    override int ShootState() { return WolfMechaTable.MECHASHOOT1; }
    override int DieState() { return WolfMechaTable.MECHADIE1; }
    override int BaseHP(int skill)
    {
        static const int HP[] = { 800, 950, 1050, 1200 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override void PostBeginPlay()
    {
        wolfSpeed = 512;
        Super.PostBeginPlay();
    }
    override int ChaseSpeedMul() { return 3; }
    override void SightSound() { A_StartSound("wolf/die", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/scheist", CHAN_VOICE); }
    override void AttackSound() { A_StartSound("wolf/bossfire", CHAN_WEAPON); }
}

// --------------------------------------------------------- Real Hitler
// Spawned by A_HitlerMorph when the mech suit dies (BOSS-004).
class WolfHitler : WolfBoss
{
    override int StateRot(int i) { return WolfHitlerTable.ROT[i]; }
    override String StateSpr(int i) { return WolfHitlerTable.SPR[i]; }
    override int StateFrm(int i) { return WolfHitlerTable.FRM[i]; }
    override int StateTics(int i) { return WolfHitlerTable.TICS[i]; }
    override int StateThink(int i) { return WolfHitlerTable.THINK[i]; }
    override int StateAction(int i) { return WolfHitlerTable.ACT[i]; }
    override int StateNext(int i) { return WolfHitlerTable.NEXT[i]; }
    override int StandState() { return WolfHitlerTable.HITLERCHASE1; }
    override int PathState() { return WolfHitlerTable.HITLERCHASE1; }
    override int ChaseState() { return WolfHitlerTable.HITLERCHASE1; }
    override int ShootState() { return WolfHitlerTable.HITLERSHOOT1; }
    override int DieState() { return WolfHitlerTable.HITLERDIE1; }
    override int BaseHP(int skill)
    {
        // A_HitlerMorph's own table (WL_ACT2.C:2888)
        static const int HP[] = { 500, 700, 800, 900 };
        return HP[Clamp(skill - 1, 0, 3)];
    }
    override void PostBeginPlay()
    {
        wolfSpeed = 512 * 5;        // SPDPATROL*5 (SPEED-008)
        Super.PostBeginPlay();
    }
    override int ChaseSpeedMul() { return 1; }
    override bool DeathCamBoss() { return true; }
    override void SightSound() { A_StartSound("wolf/die", CHAN_VOICE); }
    override void DeathSound() { A_StartSound("wolf/eva", CHAN_VOICE); }
    override void AttackSound() { A_StartSound("wolf/bossfire", CHAN_WEAPON); }
}

// ------------------------------------------------------- projectiles
// T_Projectile (WL_ACT2.C:302-360): moves speed*tics along its angle,
// clamped to 0x10000 per axis per step; hits the player inside
// PROJECTILESIZE (0xC000) on both axes; stops on walls (rockets boom).
class WolfProjectile : Actor abstract
{
    int wolfX, wolfY;
    int wolfSpeed;
    int fireAngle;          // 0-359
    int stateIdx;
    int ticcount;

    Default
    {
        +NOBLOCKMAP +NOGRAVITY +NOTELEPORT +DONTSPLASH;
        Radius 4;
        Height 16;
    }

    virtual int ProjDamage(WolfLevel wl) { return 0; }
    virtual String ProjSprite() { return "HYPO"; }
    virtual int ProjFrames() { return 4; }
    virtual bool BoomsOnWall() { return false; }

    void InitProjectile(Actor src, int speed)
    {
        wolfSpeed = speed;
        wolfX = int(src.pos.x * 1024);
        wolfY = int((4096.0 - src.pos.y) * 1024);
        fireAngle = int(src.AngleTo(players[0].mo)) % 360;
        if (fireAngle < 0)
            fireAngle += 360;
        SetOrigin(src.pos, false);
    }

    override void Tick()
    {
        if (IsFrozen())
            return;
        WolfLevel wl = WolfLevel.Get();
        if (wl == null)
            return;
        // animate
        ticcount -= 2;
        if (ticcount <= 0)
        {
            stateIdx = (stateIdx + 1) % ProjFrames();
            ticcount = 6;
            frame = stateIdx;
        }

        int move = wolfSpeed * 2;
        double rad = fireAngle * (3.14159265 / 180.0);
        int dx = int(cos(fireAngle) * move);
        int dy = int(-sin(fireAngle) * move);
        wolfX += Clamp(dx, -0x10000, 0x10000);
        wolfY += Clamp(dy, -0x10000, 0x10000);

        int tx = wolfX >> 16, ty = wolfY >> 16;
        int st;
        WolfDoor dd;
        [st, dd] = wl.TileState(tx, ty);
        if (st != 0)                        // wall or closed door
        {
            if (BoomsOnWall())
                A_StartSound("wolf/missilehit", CHAN_AUTO);
            Destroy();
            return;
        }
        SetOrigin((wolfX / 1024.0, 4096.0 - wolfY / 1024.0, 20), true);

        PlayerPawn pm = players[0].mo;
        if (pm != null && pm.health > 0)
        {
            int px = int(pm.pos.x * 1024), py = int((4096.0 - pm.pos.y) * 1024);
            if (abs(wolfX - px) < 0xC000 && abs(wolfY - py) < 0xC000)
            {
                int dmg = ProjDamage(wl);
                if (dmg > 0)
                    pm.DamageMobj(self, self, dmg, 'Bullet', DMG_THRUSTLESS);
                Destroy();
            }
        }
    }
}

class WolfNeedle : WolfProjectile          // PROJ-002
{
    override int ProjDamage(WolfLevel wl) { return (wl.RndT() >> 3) + 20; }
    override String ProjSprite() { return "HYPO"; }
    States { Spawn: HYPO ABCD 6; Loop; }
}

class WolfRocket : WolfProjectile          // PROJ-001
{
    override int ProjDamage(WolfLevel wl) { return (wl.RndT() >> 3) + 30; }
    override bool BoomsOnWall() { return true; }
    override int ProjFrames() { return 1; }
    States { Spawn: MISL A -1; Stop; }
}

class WolfFire : WolfProjectile            // PROJ-003
{
    override int ProjDamage(WolfLevel wl) { return wl.RndT() >> 3; }
    override int ProjFrames() { return 2; }
    States { Spawn: FIRE AB 6; Loop; }
}
