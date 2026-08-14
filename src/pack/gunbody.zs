// SHIPPED INSIDE wolfvox.pk3, not in the base game.
// The weapon, as its own actor.
//
// The gun is NOT baked into the body models. Two measured reasons: the
// uniform recolor would paint it (338 of the gun's 1147 voxels in a
// firing pose fall inside the uniform's colour band), and a baked gun
// costs four copies - one per uniform - of every pose, with every extra
// weapon multiplying that again. Separate, one gun serves all four
// uniforms and a second weapon is one more small set.
//
// It needs no offset or rotation maths: each gun model was posed by the
// same clip at the same instant as its body frame and then pivoted at
// the BODY's pivot (tools/voxel/align_anchors.py), so drawing it at the
// player's own position and angle puts it in his hands by construction.
// The follower only has to mirror which frame the body is showing.
class WolfGunBody : Actor
{
    // WolfPlayer.voxKind -> the gun set posed by that clip. The kinds
    // are the player's own, so nothing here has to reverse-engineer a
    // sprite name, and the uniform recolor (which moves the BODY to
    // BJ2/3/4 and leaves the gun alone) cannot confuse it.
    static const name GUNSPR[] = { 'WGNS', 'WGNW', 'WGNA', 'WGNP', 'WGND' };

    Default
    {
        +NOBLOCKMAP
        +NOINTERACTION
        +NOGRAVITY
        +NOTONAUTOMAP
        +DONTSPLASH
    }

    int sprGun[5];
    bool inited;

    States
    {
    // Sprite-name registration only, never entered: GetSpriteIndex
    // returns -1 for a name no state ever mentions, even when the sprite
    // lumps are present. This class lives in the voxel pack precisely so
    // these frames are guaranteed to exist alongside it.
    Spawn:
        WGNS ABCDEFG -1;
        WGNW ABCDEF -1;
        WGNA ABC -1;
        WGNP AB -1;
        WGND ABCDEFG -1;
        Stop;
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
        if (!inited)
        {
            inited = true;
            for (int i = 0; i < 5; i++)
                sprGun[i] = GetSpriteIndex(GUNSPR[i]);
        }
        // voxKind: 1 idle, 2 run, 3 shoot, 4 death, 5 pain
        int k = p.voxKind - 1;
        SetOrigin(p.Vec3Offset(0, 0, 0), true);
        if (k < 0 || k > 4 || sprGun[k] <= 0)
        {
            bInvisible = true;       // no gun set for this state
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
        sprite = sprGun[k];
        frame = p.frame;
        angle = p.angle;
    }

}
