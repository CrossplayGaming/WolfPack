// SHIPPED INSIDE wolfvox.pk3, not in the base game.
// The weapon, as its own actor.
//
// The gun is NOT baked into the body models. Two measured reasons: the
// uniform recolor would paint it (338 of the gun's 1147 voxels in a
// firing pose fall inside the uniform's colour band), and a baked gun
// costs four copies - one per uniform - of every pose, with every extra
// weapon multiplying that again. Separate, one weapon model serves all
// four uniforms and a new weapon is one more small set.
//
// It needs no offset or rotation maths: each weapon model was posed by
// the same clip at the same instant as its body frame and then pivoted
// at the BODY's pivot (tools/voxel/align_anchors.py), so drawing it at
// the player's own position and angle puts it in his hands by
// construction. The follower only mirrors which frame the body shows.
class WolfGunBody : Actor
{
    Default
    {
        +NOBLOCKMAP
        +NOINTERACTION
        +NOGRAVITY
        +NOTONAUTOMAP
        +DONTSPLASH
    }

    States
    {
    // Sprite-name registration only, never entered: GetSpriteIndex
    // returns -1 for a name no state ever mentions, even when the
    // sprite lumps are present. This class lives in the voxel pack
    // precisely so these frames are guaranteed to exist alongside it.
    // The pack-only BODY sets (directional fire, backward walk, stab)
    // register here too - the base game's SkinReg cannot name them
    // without becoming a load error for everyone without the pack.
    Spawn:
        WGNS ABCDEFG -1;
        WGNW ABCDEF -1;
        WGNP AB -1;
        WGND ABCDEFG -1;
        WGNB ABCDEFG -1;
        WGNL ABCDEF -1;
        WGNM ABCDEF -1;
        WPSS ABCDEFG -1;
        WPSW ABCDEF -1;
        WPSP AB -1;
        WPSD ABCDEFG -1;
        WPSB ABCDEFG -1;
        WPSG ABCDEFG -1;
        WPSK ABCDEFG -1;
        WKNS ABCDEFG -1;
        WKNW ABCDEF -1;
        WKNP AB -1;
        WKND ABCDEFG -1;
        WKNB ABCDEFG -1;
        WKNT ABCDE -1;
        WBZS ABCDEFG -1;
        WBZW ABCDEF -1;
        WBZP AB -1;
        WBZD ABCDEFG -1;
        WBZB ABCDEFG -1;
        WBZL ABCDEF -1;
        WBZM ABCDEF -1;
        FMGL ABCDEF -1;
        FMGM ABCDEF -1;
        FPSG ABCDEFG -1;
        FPSK ABCDEFG -1;
        FBZL ABCDEF -1;
        FBZM ABCDEF -1;
        BJ1G ABCDEFG -1; BJ2G ABCDEFG -1;
        BJ3G ABCDEFG -1; BJ4G ABCDEFG -1;
        BJ1K ABCDEFG -1; BJ2K ABCDEFG -1;
        BJ3K ABCDEFG -1; BJ4K ABCDEFG -1;
        BJ1L ABCDEF -1; BJ2L ABCDEF -1;
        BJ3L ABCDEF -1; BJ4L ABCDEF -1;
        BJ1M ABCDEF -1; BJ2M ABCDEF -1;
        BJ3M ABCDEF -1; BJ4M ABCDEF -1;
        BJ1B ABCDEFG -1; BJ2B ABCDEFG -1;
        BJ3B ABCDEFG -1; BJ4B ABCDEFG -1;
        BJ1T ABCDE -1; BJ2T ABCDE -1;
        BJ3T ABCDE -1; BJ4T ABCDE -1;
        Stop;
    }

    // kind (1..8) x weapon (1 MG, 2 pistol, 3 knife, 4 chaingun)
    // -> weapon
    // sprite. The kinds are the player's own, so nothing here
    // reverse-engineers a sprite name, and the uniform recolor (which
    // moves the BODY to BJ2/3/4 and leaves the weapon alone) cannot
    // confuse it.
    name GunSprName(int kind, int wep)
    {
        if (wep == 1)
        {
            switch (kind)
            {
            case 1: return 'WGNS';
            case 2: return 'WGNW';
            case 3: return 'WGNB';
            case 4: return 'WGND';
            case 5: return 'WGNP';
            case 6: return 'WGNL';
            case 7: return 'WGNM';
            }
        }
        else if (wep == 2)
        {
            switch (kind)
            {
            case 1: return 'WPSS';
            case 2: return 'WPSW';
            case 3: return 'WPSB';
            case 4: return 'WPSD';
            case 5: return 'WPSP';
            case 6: return 'WPSG';
            case 7: return 'WPSK';
            }
        }
        else if (wep == 3)
        {
            switch (kind)
            {
            case 1: return 'WKNS';
            case 2: return 'WKNW';
            case 3: return 'WKNB';
            case 4: return 'WKND';
            case 5: return 'WKNP';
            case 8: return 'WKNT';
            }
        }
        else if (wep == 4)      // chaingun ("bazooka" in the grip data)
        {
            switch (kind)
            {
            case 1: return 'WBZS';
            case 2: return 'WBZW';
            case 3: return 'WBZB';
            case 4: return 'WBZD';
            case 5: return 'WBZP';
            case 6: return 'WBZL';
            case 7: return 'WBZM';
            }
        }
        return 'None';
    }

    override void Tick()
    {
        // no Super.Tick(): position and frame are a pure function of the
        // player's, recomputed here
        let p = WolfPlayer(master);
        if (p == null)
            return;                 // summoned standalone: just sit there
        if (p.player == null || p.player.mo != p)
        {
            Destroy();
            return;
        }
        SetOrigin(p.Vec3Offset(0, 0, 0), true);

        name sn = GunSprName(p.voxKind, p.VoxWeapon());
        int id = sn == 'None' ? -1 : GetSpriteIndex(sn);
        if (id <= 0)
        {
            bInvisible = true;      // no weapon set for this state/weapon
            return;
        }
        // FIRST PERSON: the engine hides a player's own pawn from his
        // own camera, but this is a separate actor, so his gun hung in
        // the middle of his own view. Hide it for exactly one viewer -
        // the node whose local player is looking through his own eyes.
        //
        // Per NODE deliberately, not per player: hiding it from the
        // owner's SIM state would also hide it from everyone else
        // watching him, and in a netgame the man in first person is
        // precisely the one whose weapon other players need to see.
        // bInvisible on a NOINTERACTION actor is render-only - it
        // cannot collide, think or influence anything - so a value that
        // differs between nodes cannot move the simulation apart.
        bInvisible = (p.player == players[consoleplayer]
                      && p.player.camera == p);
        // transition probe (wolf_dbg_check): log the tic whenever the
        // gun's set changes, to measure lag against the body's switch
        CVar dbg = CVar.FindCVar("wolf_dbg_check");
        if (dbg != null && dbg.GetInt() != 0 && sprite != id)
            Console.Printf("GUNSWAP t=%d -> %s", Level.maptime, sn);
        sprite = id;
        frame = p.frame;
        angle = p.angle;
    }
}
