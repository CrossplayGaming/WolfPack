// WolfPlayer — Phase 1 bootstrap player.
//
// Charter (checklist §3): camera height is CONSTANT at half wall height —
// Wolf renders the eye at the tile midplane, i.e. 32 of our 64-unit walls —
// and there is no view bob and no weapon bob (MOVE-00x family; the
// Modernization menu later re-exposes bob as an OFF-default toggle).
//
// Doom fist/pistol are TEMPORARY placeholders until the Phase 2 weapon set
// (knife/pistol/machine gun/chaingun with WEAP-001..005 cadences) lands.
class WolfPlayer : DoomPlayer
{
    Default
    {
        Player.ViewHeight 32;
        Height 56;
        Player.ViewBob 0;       // no view bob, no weapon bob (1992 default)
    }
}
