// Enhanced lighting (Modernization: wolf_mod_light + Lighting page).
//
// Wolf renders fullbright; dynamic lights are invisible in a fullbright
// room (nothing can get brighter). So the master toggle does the two
// world-state halves together, host-controlled like flats:
//
//   1. DEPTH SHADING: every sector drops from 255 to LIGHT_LEVEL with
//      the engine's distance falloff doing the rest. Restore-on-off
//      keeps classic mode classic to the pixel.
//   2. POOL SWAP: hanging fixtures carry a PAINTED floor light-pool
//      baked into their sprite (Eric's catch). gen_lighting.py ships
//      pool-less frame-B variants and lists the affected classes in
//      wolfdata/lighting.txt; while enhanced lighting is on, those
//      fixtures show frame B and the dynamic light provides the real
//      pool.
//
// The render-side toggles (gl_lights, gl_lightmode, shadowmaps, SSAO,
// bloom) are per-player local cvars set by the menu, not here.

class WolfLighting : EventHandler
{
    // 184 with Vanilla falloff read as Doom 3 - long Wolf corridors hit
    // near-black (measured far-wall 36/255). 200 + Software mode keeps
    // rooms readable while distance still recedes.
    const LIGHT_LEVEL = 200;

    bool appliedNow;
    Array<int> sects;               // sectors we dimmed
    Array<String> swapClasses;      // fixture classes with a pool-less
    Array<String> swapSprites;      // ...sprite name (XPnn), paired

    // Lights are ATTACHED AT RUNTIME, not declared in GLDEFS. A GLDEFS
    // `object X { frame Y { light Z } }` binds the light to the sprite
    // permanently - nothing about it can be conditional - so the lamps
    // and the projectiles kept glowing with enhanced lighting switched
    // off (user report: "some dynamic light setting stuck on"). The
    // table now ships as wolfdata/lights.txt and this attaches or
    // removes the lights with the option.
    const LIGHTTAG = "wolfmod";
    Array<String> litClass;
    Array<int> litR, litG, litB, litSize, litZ;

    static bool Wanted()
    {
        CVar cv = CVar.GetCVar("wolf_mod_light", players[0]);
        return cv != null && cv.GetInt() != 0;
    }

    override void WorldLoaded(WorldEvent e)
    {
        appliedNow = false;
        swapClasses.Clear();
        int lump = Wads.CheckNumForFullName("wolfdata/lighting.txt");
        if (lump >= 0)
        {
            String raw = Wads.ReadLump(lump);
            Array<String> rows;
            raw.Split(rows, "\n");
            swapSprites.Clear();
            for (int i = 0; i < rows.Size(); i++)
            {
                String r = rows[i];
                int L = r.Length();
                if (L > 0 && r.ByteAt(L - 1) == 13)
                    r = r.Left(L - 1);          // CRLF, the flats lesson
                Array<String> f;
                r.Split(f, " ");
                if (f.Size() >= 2)
                {
                    swapClasses.Push(f[0]);
                    swapSprites.Push(f[1]);
                }
            }
        }
        litClass.Clear(); litR.Clear(); litG.Clear();
        litB.Clear(); litSize.Clear(); litZ.Clear();
        int llump = Wads.CheckNumForFullName("wolfdata/lights.txt");
        if (llump >= 0)
        {
            Array<String> rows;
            Wads.ReadLump(llump).Split(rows, "\n");
            for (int i = 0; i < rows.Size(); i++)
            {
                String r = rows[i];
                int L = r.Length();
                if (L > 0 && r.ByteAt(L - 1) == 13)
                    r = r.Left(L - 1);          // CRLF, the flats lesson
                Array<String> f;
                r.Split(f, " ");
                if (f.Size() < 6)
                    continue;
                litClass.Push(f[0]);
                litR.Push(f[1].ToInt()); litG.Push(f[2].ToInt());
                litB.Push(f[3].ToInt());
                litSize.Push(f[4].ToInt()); litZ.Push(f[5].ToInt());
            }
        }
        if (Wanted())
            Apply(true);
    }

    // index into the light table for an actor's class, or -1
    int LightFor(Actor a)
    {
        for (int i = 0; i < litClass.Size(); i++)
            if (a is litClass[i])
                return i;
        return -1;
    }

    void SetLight(Actor a, int i, bool on)
    {
        if (!on)
        {
            a.A_RemoveLight(LIGHTTAG);
            return;
        }
        a.A_AttachLight(LIGHTTAG, DynamicLight.PointLight,
                        Color(255, litR[i], litG[i], litB[i]),
                        litSize[i], litSize[i], 0,
                        (0, 0, litZ[i]));
    }

    // projectiles are spawned mid-match, long after Apply ran
    override void WorldThingSpawned(WorldEvent e)
    {
        if (!appliedNow || e.Thing == null)
            return;
        int i = LightFor(e.Thing);
        if (i >= 0)
            SetLight(e.Thing, i, true);
    }

    override void WorldTick()
    {
        if (Level.maptime % 10 != 0)
            return;
        bool want = Wanted();
        if (want != appliedNow)
            Apply(want);
    }

    void Apply(bool on)
    {
        // depth shading: uniform dim from fullbright; every Wolf sector
        // is 255, so restore is a constant too - no per-sector book-
        // keeping to drift
        for (int i = 0; i < Level.Sectors.Size(); i++)
            Level.Sectors[i].SetLightLevel(on ? LIGHT_LEVEL : 255);

        // painted-pool swap: point the fixture at the pool-less
        // SPRITE (own name, registered below). Swapping frames of the
        // original sprite rendered invisible - frame B never entered
        // the sprite def built from an A-only States block.
        for (int c = 0; c < swapClasses.Size(); c++)
        {
            class<Actor> cls = swapClasses[c];
            if (cls == null)
                continue;
            int poolless = GetDefaultByType(cls).GetSpriteIndex(
                swapSprites[c]);
            ThinkerIterator it = ThinkerIterator.Create(cls);
            Actor a;
            while ((a = Actor(it.Next())) != null)
            {
                if (on && poolless >= 0)
                {
                    a.sprite = poolless;
                    a.frame = 0;
                }
                else
                    a.SetState(a.SpawnState);   // exact original look
            }
        }

        // attach or strip the dynamic lights themselves
        for (int i = 0; i < litClass.Size(); i++)
        {
            ThinkerIterator it = ThinkerIterator.Create(litClass[i]);
            Actor a;
            while ((a = Actor(it.Next())) != null)
                SetLight(a, i, on);
        }
        appliedNow = on;
    }
}


// Never spawned: its States block exists solely to REGISTER the
// pool-less sprite names (playbook: sprite lumps do not register
// names on their own). Same XP names in both game sets by design.
class WolfPoollessFrames : Actor
{
    States
    {
    Spawn:
    P04:
        XP04 A -1;
        Stop;
    P14:
        XP14 A -1;
        Stop;
    }
}
