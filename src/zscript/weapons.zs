// Wolf player weapons — charter WEAP-001..005, PCOMBAT-001..003, KNIFE-001/002.
//
// Cadence: attackinfo (WL_AGENT.C:64-73) — every weapon runs 4 frames of
// 6 Wolf tics = 3 engine tics. Knife/pistol are strictly per-press
// (Cmd_Fire is edge-triggered -> WEAPON.NOAUTOFIRE); machine gun loops
// fire+rewind frames (1 shot/12 Wolf tics held); chaingun fires on both
// loop frames (2 shots/12).
//
// Damage uses the sim's US_RndT stream. Target pick (GunAttack,
// WL_AGENT.C:1168-1242): closest candidate within shootdelta of screen
// center (viewwidth/10 -> ~7.5 deg half-cone, WL_MAIN.C:1283) with LOS.

class WolfAmmo : Ammo
{
    Default
    {
        Inventory.MaxAmount 99;         // SCORE-004 cap
        Inventory.Amount 1;
        Inventory.Icon "N_BLANK";
    }
}

class WolfWeapon : Weapon abstract
{
    Default
    {
        Weapon.KickBack 0;
        Weapon.YAdjust 16;          // rest on the screen bottom in fullscreen
        +WEAPON.NOALERT             // sim's madenoise handles alerting
        +WEAPON.DONTBOB
    }

    // GunAttack (WL_AGENT.C:1168-1242)
    action void A_WolfGun()
    {
        WolfLevel wl = WolfLevel.Get();
        if (wl == null) return;
        if (invoker.Ammo1 == null || invoker.Ammo1.Amount <= 0)
            return;
        invoker.Ammo1.Amount--;
        invoker.AttackSnd();
        wl.noisePending = true;
        // the voxel pack's muzzle flash blinks for the couple of tics
        // after each ACTUAL shot - set here, where the shot really
        // happens, so dry-fire and wind-up never flash. Plain pawn
        // field: replicated sim state, harmless without the pack.
        let wp = WolfPlayer(self);
        if (wp != null)
            wp.voxFlash = 3;

        Actor target = FindCenterTarget(96.0, 999999.0);
        if (target == null)
            return;
        int ptx = int(pos.x) / 64, pty = 63 - (int(pos.y) / 64);
        int etx = int(target.pos.x) / 64, ety = 63 - (int(target.pos.y) / 64);
        int dist = Max(abs(ptx - etx), abs(pty - ety));
        int damage;
        if (dist < 2)
            damage = wl.RndT() / 4;
        else if (dist < 4)
            damage = wl.RndT() / 6;
        else
        {
            if (wl.RndT() / 12 < dist)
                return;                 // missed
            damage = wl.RndT() / 6;
        }
        if (damage > 0)
            target.DamageMobj(self, self, damage, 'Bullet', DMG_THRUSTLESS);
    }

    // KnifeAttack (WL_AGENT.C:1133-1164): depth <= 0x18000 = 1.5 tiles
    action void A_WolfKnife()
    {
        WolfLevel wl = WolfLevel.Get();
        if (wl == null) return;
        invoker.AttackSnd();
        Actor target = FindCenterTarget(96.0, 96.0);
        if (target != null)
        {
            int damage = wl.RndT() >> 4;
            if (damage > 0)
                target.DamageMobj(self, self, damage, 'Melee', DMG_THRUSTLESS);
        }
    }

    // closest shootable within the aim cone and LOS (transx ordering
    // approximated by distance; DEC-004)
    action Actor FindCenterTarget(double coneDist0, double maxDepth)
    {
        Actor best = null;
        double bestDist = maxDepth;
        ThinkerIterator it = ThinkerIterator.Create("Actor");
        Actor a;
        while ((a = Actor(it.Next())) != null)
        {
            if (!a.bShootable || a == self)
                continue;
            double d = Distance2D(a);
            if (d > bestDist)
                continue;
            if (absangle(AngleTo(a), Angle) > 7.5)
                continue;
            if (!CheckSight(a))
                continue;
            best = a;
            bestDist = d;
        }
        return best;
    }

    // attackinfo rewind (codes 3 and 4, WL_AGENT.C:1367-1370): at the END
    // of the frame, if ammo remains and fire is held, step back to the
    // fire frame. Placed in a 0-tic state so the preceding frame's full
    // duration elapses first (cadence WEAP-003/004).
    action state A_WolfRewind(statelabel target)
    {
        if (player == null)
            return ResolveState(null);
        bool held = (player.cmd.buttons & BT_ATTACK) != 0;
        CVar ff = CVar.FindCVar("wolf_dbg_forcefire");   // harness only
        if (ff != null && ff.GetInt() != 0)
            held = true;
        if (held && invoker.Ammo1 != null && invoker.Ammo1.Amount > 0)
        {
            player.refire++;
            return ResolveState(target);
        }
        player.refire = 0;
        return ResolveState(null);
    }

    virtual void AttackSnd() {}
}

class WolfKnife : WolfWeapon
{
    override void AttackSnd() { Owner.A_StartSound("wolf/knife", CHAN_WEAPON); }
    Default
    {
        Weapon.SlotNumber 1;   // original key 1
        Weapon.SelectionOrder 4;
        +WEAPON.NOAUTOFIRE
        +WEAPON.MELEEWEAPON
    }
    States
    {
    Ready:
        WKNF A 1 A_WeaponReady;
        Loop;
    Select:
        WKNF A 1 A_Raise;
        Loop;
    Deselect:
        WKNF A 1 A_Lower;
        Loop;
    Fire:
        WKNF B 3;
        WKNF C 3 A_WolfKnife;
        WKNF D 3;
        WKNF E 3;
        Goto Ready;
    }
}

class WolfPistol : WolfWeapon
{
    Default
    {
        Weapon.SlotNumber 2;   // original key 2
        Weapon.SelectionOrder 3;
        Weapon.AmmoType1 "WolfAmmo";
        Weapon.AmmoUse1 1;
        Weapon.AmmoGive1 0;
        +WEAPON.NOAUTOFIRE
    }
    override void AttackSnd() { Owner.A_StartSound("wolf/pistol", CHAN_WEAPON); }
    States
    {
    Ready:
        WPIS A 1 A_WeaponReady;
        Loop;
    Select:
        WPIS A 1 A_Raise;
        Loop;
    Deselect:
        WPIS A 1 A_Lower;
        Loop;
    Fire:
        WPIS B 3;
        WPIS C 3 A_WolfGun;
        WPIS D 3;
        WPIS E 3;
        Goto Ready;
    }
}

class WolfMachineGun : WolfWeapon
{
    Default
    {
        Weapon.SlotNumber 3;   // original key 3
        Weapon.SelectionOrder 2;
        Weapon.AmmoType1 "WolfAmmo";
        Weapon.AmmoUse1 1;
        Weapon.AmmoGive1 6;             // GiveWeapon +6 (PICK-009)
    }
    override void AttackSnd() { Owner.A_StartSound("wolf/machinegun", CHAN_WEAPON); }
    States
    {
    Ready:
        WMGN A 1 A_WeaponReady;
        Loop;
    Select:
        WMGN A 1 A_Raise;
        Loop;
    Deselect:
        WMGN A 1 A_Lower;
        Loop;
    Fire:
        WMGN B 3;
    Hold:
        WMGN C 3 A_WolfGun;
        WMGN D 3;
        WMGN D 0 A_WolfRewind("Hold");
        WMGN E 3;
        Goto Ready;
    }
}

class WolfChaingun : WolfWeapon
{
    Default
    {
        Weapon.SlotNumber 4;   // original key 4
        Weapon.SelectionOrder 1;
        Weapon.AmmoType1 "WolfAmmo";
        Weapon.AmmoUse1 1;
        Weapon.AmmoGive1 6;
    }
    override void AttackSnd() { Owner.A_StartSound("wolf/gatling", CHAN_WEAPON); }
    States
    {
    Ready:
        WCHN A 1 A_WeaponReady;
        Loop;
    Select:
        WCHN A 1 A_Raise;
        Loop;
    Deselect:
        WCHN A 1 A_Lower;
        Loop;
    Fire:
        WCHN B 3;
    Hold:
        WCHN C 3 A_WolfGun;
        WCHN D 3 A_WolfGun;
        WCHN D 0 A_WolfRewind("Hold");
        WCHN E 3;
        Goto Ready;
    }
}
