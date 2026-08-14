// Open-roof third person: while ANYONE is in third person, every
// ceiling becomes sky, so the chase camera can rise above the map and
// see the level dollhouse-style. The moment the last player returns to
// first person, the exact ceilings come back - the classic solid
// colour, or the textured ceilings if Floor + Ceiling Textures is on.
//
// The swap is invisible from below in classic mode BY CONSTRUCTION:
// each level's sky1 is generated as that level's own CEILxx flat
// (gen_mapinfo.py), so the "sky" is the same solid colour the ceiling
// was. Only flats mode shows the change (texture -> colour), which is
// the price of seeing over the walls.
//
// Sector textures are SHARED SIM STATE, so the trigger must be
// derivable identically on every node: wolf_mod_tp is a replicated
// user cvar, and "any player has it on" is the same answer everywhere.
// In a netgame that means one player entering third person opens the
// roof for everyone - in classic mode nobody in first person can tell.
class WolfSkyCeil : EventHandler
{
    bool skyOn;
    Array<TextureID> saved;         // per-sector ceiling, index = sector

    static clearscope bool AnyThirdPerson()
    {
        for (int i = 0; i < MAXPLAYERS; i++)
        {
            if (!playeringame[i])
                continue;
            CVar cv = CVar.GetCVar("wolf_mod_tp", players[i]);
            if (cv != null && cv.GetInt() != 0)
                return true;
        }
        return false;
    }

    override void WorldLoaded(WorldEvent e)
    {
        skyOn = false;
        saved.Clear();
    }

    override void WorldTick()
    {
        bool want = AnyThirdPerson() && Level.MapName != "TITLEMAP";
        if (want == skyOn)
            return;
        TextureID sky = TexMan.CheckForTexture("F_SKY1",
                                               TexMan.Type_Flat);
        if (!sky.IsValid())
            return;
        if (want)
        {
            saved.Resize(Level.sectors.Size());
            for (int i = 0; i < Level.sectors.Size(); i++)
            {
                saved[i] = Level.sectors[i].GetTexture(Sector.ceiling);
                Level.sectors[i].SetTexture(Sector.ceiling, sky);
            }
        }
        else
        {
            for (int i = 0; i < Level.sectors.Size()
                 && i < saved.Size(); i++)
                Level.sectors[i].SetTexture(Sector.ceiling, saved[i]);
        }
        skyOn = want;
    }
}
