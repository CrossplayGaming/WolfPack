// Textured floors and ceilings (Modernization: wolf_mod_flats).
//
// Wolf renders solid-colour planes; this optional layer assigns real
// textures per AREA, driven by each area's dominant wall through the
// hand-vetoed pair table (docs/data/flat_pairs.json -> per-map
// wolfdata/MAPNN.flats sidecars, gen_flats.py). Areas only connect
// through doors, so a flat change always happens under a doorframe -
// the seam is masked by construction, the same trick Blake Stone used.
//
// Host-controlled like the other world-level toggles (jump/crouch):
// every node applies from PLAYER 0's replicated user cvar, so the
// world agrees in co-op. Purely cosmetic - nothing in the sim reads
// plane textures - but one world, one look.
//
// Sectors are per-area (converter), so application is: first floor
// tile of each area -> PointInSector -> SetTexture on both planes.
// Originals are captured before the first swap and restored exactly on
// toggle-off, so OFF is the classic game to the pixel.

class WolfFlats : EventHandler
{
    // per-sector originals, captured lazily on first apply
    bool captured;
    bool appliedNow;
    Array<int> sects;
    Array<TextureID> origFloor;
    Array<TextureID> origCeil;
    Array<TextureID> newFloor;
    Array<TextureID> newCeil;

    static bool Wanted()
    {
        // host decides; in SP player 0 IS the host
        CVar cv = CVar.GetCVar("wolf_mod_flats", players[0]);
        return cv != null && cv.GetInt() != 0;
    }

    override void WorldLoaded(WorldEvent e)
    {
        captured = false;
        appliedNow = false;
        Parse();
        if (Wanted())
            Apply(true);
    }

    override void WorldTick()
    {
        // follow mid-level toggles (menu writes the cvar; watch it)
        if (Level.maptime % 10 != 0)
            return;
        bool want = Wanted();
        if (want != appliedNow && sects.Size() > 0)
            Apply(want);
    }

    void Parse()
    {
        sects.Clear(); origFloor.Clear(); origCeil.Clear();
        newFloor.Clear(); newCeil.Clear();
        int lump = Wads.CheckNumForFullName(
            String.Format("wolfdata/%s.flats", Level.mapname));
        if (lump < 0)
            return;                     // set without a table (sod, lobby)
        WolfLevel wl = WolfLevel.Get();
        if (wl == null)
            return;
        Array<String> rows;
        Wads.ReadLump(lump).Split(rows, "\n");
        for (int i = 0; i < rows.Size(); i++)
        {
            Array<String> f;
            rows[i].Split(f, " ");
            if (f.Size() < 3 || f[0].Length() < 1)
                continue;
            // strip a trailing CR byte explicitly: the sidecars are
            // CRLF and String.Replace on the whole lump did NOT take
            // (measured: floor lookup still failed while the mid-line
            // ceiling field worked). Byte-level, no API semantics.
            for (int k = 0; k < f.Size(); k++)
            {
                int L = f[k].Length();
                if (L > 0 && f[k].ByteAt(L - 1) == 13)
                    f[k] = f[k].Left(L - 1);
            }
            // door line: "T x y CEIL FLOOR" - tile-addressed, the
            // neighboring room's pair runs under the door
            if (f[0] == "T" && f.Size() >= 5)
            {
                int tx = f[1].ToInt(), ty = f[2].ToInt();
                Sector ds = Level.PointInSector(
                    (tx * 64 + 32.0, (63 - ty) * 64 + 32.0));
                if (ds != null)
                {
                    sects.Push(ds.Index());
                    origCeil.Push(ds.GetTexture(Sector.ceiling));
                    origFloor.Push(ds.GetTexture(Sector.floor));
                    newCeil.Push(TexMan.CheckForTexture(
                        f[3], TexMan.Type_Any));
                    newFloor.Push(TexMan.CheckForTexture(
                        f[4], TexMan.Type_Any));
                }
                continue;
            }
            int area = f[0].ByteAt(0) - 65;
            // find a floor tile of this area -> its sector
            bool found = false;
            for (int t = 0; t < 4096 && !found; t++)
            {
                if (wl.AreaAt(t % 64, t / 64) != area)
                    continue;
                Vector2 wpos = ((t % 64) * 64 + 32.0,
                                (63 - t / 64) * 64 + 32.0);
                Sector s = Level.PointInSector(wpos);
                if (s == null)
                    continue;
                found = true;
                sects.Push(s.Index());
                origCeil.Push(s.GetTexture(Sector.ceiling));
                origFloor.Push(s.GetTexture(Sector.floor));
                newCeil.Push(TexMan.CheckForTexture(
                    f[1], TexMan.Type_Any));
                newFloor.Push(TexMan.CheckForTexture(
                    f[2], TexMan.Type_Any));
            }
        }
    }

    void Apply(bool on)
    {
        for (int i = 0; i < sects.Size(); i++)
        {
            Sector s = Level.Sectors[sects[i]];
            TextureID c = on ? newCeil[i] : origCeil[i];
            TextureID fl = on ? newFloor[i] : origFloor[i];
            if (c.IsValid())
                s.SetTexture(Sector.ceiling, c);
            if (fl.IsValid())
                s.SetTexture(Sector.floor, fl);
        }
        appliedNow = on;
    }
}
