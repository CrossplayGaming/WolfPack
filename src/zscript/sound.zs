// Wolf's sound priorities (ID_SD.C) - the REFUSAL half of them.
//
// Wolf does not mix. The Sound Blaster plays ONE digitized sound at a
// time and the AdLib chip ONE effect, so SD_PlaySound is a gate rather
// than a mixer, with two halves:
//
//     if (s->priority < DigiPriority)      // ID_SD.C:2169, digitized
//         return(false);                   // ID_SD.C:2185, AdLib
//     ...play it - which REPLACES whatever the slot held
//
// REFUSAL is what makes the original sound composed: a door (20) stays
// silent under a death cry (99), treasure (70) never steps on the
// machine gun pickup (80). That half is implemented here, with the
// priorities read out of each AdLib chunk header at build time
// (tools/gen_sndpriority.py -> wolfdata/sndprio.txt) and the slot
// falling back to 0 when its sound ends (SDL_DigitizedDone,
// ID_SD.C:1184 - stood in for by the end tic below).
//
// REPLACEMENT is deliberately NOT implemented. On one mono channel it
// was invisible - there was never a second sound to lose - but nearly
// everything in a firefight is priority 50 (every weapon, every "Halt",
// every death cry, NAZIFIRESND), so a faithful replace makes each new
// shot silence each dying guard, and on a positional stereo engine that
// reads as sounds being killed left and right (owner report, 0.9.9).
// This engine can mix, so an accepted sound simply plays ALONGSIDE the
// slot's current one on the channel the caller asked for. Wolf is one
// player at one place, so the two slots stay GLOBAL, as they were in
// hardware; in a netgame a distant player's pickup can still hold one.
//
// Names missing from the table - the engine's own menu/* set - bypass
// the gate entirely.

class WolfSnd : EventHandler
{
    const SLOTS = 2;            // 0 = digitized, 1 = AdLib

    Array<String> sndName;
    Array<int> sndPrio, sndSlot;
    bool tableLoaded;

    int slotPrio[SLOTS];        // priority the slot currently holds
    int slotEnd[SLOTS];         // level.time that sound finishes

    static WolfSnd Get() { return WolfSnd(EventHandler.Find("WolfSnd")); }

    override void WorldLoaded(WorldEvent e)
    {
        LoadTable();
        for (int i = 0; i < SLOTS; i++)
        {
            slotPrio[i] = 0;
            slotEnd[i] = 0;
        }
    }

    void LoadTable()
    {
        if (tableLoaded)
            return;
        tableLoaded = true;
        int lump = Wads.CheckNumForFullName("wolfdata/sndprio.txt");
        if (lump < 0)
            return;
        Array<String> rows;
        Wads.ReadLump(lump).Split(rows, "\n");
        for (int i = 0; i < rows.Size(); i++)
        {
            Array<String> f;
            rows[i].Split(f, " ");
            if (f.Size() < 3)
                continue;
            sndName.Push(f[0]);
            sndPrio.Push(f[1].ToInt());
            sndSlot.Push(f[2].ToInt());
        }
    }

    int Lookup(String snd)
    {
        for (int i = 0; i < sndName.Size(); i++)
            if (sndName[i] == snd)
                return i;
        return -1;
    }

    // SD_PlaySound's refusal (ID_SD.C:2169/2185) for one emitter. An
    // accepted sound takes over the slot's record - its priority and
    // its end tic - and plays on the caller's own channel, next to
    // whatever was already sounding; nothing is stopped.
    void Gate(Actor origin, String snd, int chan,
              double volume, double attenuation)
    {
        LoadTable();
        int i = Lookup(snd);
        if (i >= 0)
        {
            int slot = sndSlot[i];
            if (level.time >= slotEnd[slot])
                slotPrio[slot] = 0;             // the slot has run dry
            if (sndPrio[i] < slotPrio[slot])
                return;                         // refused, never played
            slotPrio[slot] = sndPrio[i];
            slotEnd[slot] = level.time
                          + max(1, int(S_GetLength(snd) * 35.0));
        }
        origin.A_StartSound(snd, chan, volume: volume,
                            attenuation: attenuation);
    }

    // A_Slurpie: off the gate AND off the emitter's voice channel.
    //
    // Hitler's last words (EVASND) and the melt (SLURPIESND) are both
    // priority 99, so the gate alone would already let the melt start -
    // but DeathSound() speaks on CHAN_VOICE, and a second sound on the
    // same actor's same channel replaces the first at the engine level,
    // which is exactly the 0.29s cut the original had (A_Slurpie fires
    // from the action slot of s_hitlerdie3, twenty tics after
    // A_DeathScream; the Angel's death in Spear has the same shape).
    // Owner's call: the line plays in full, the melt layers under it on
    // a channel of its own. It neither takes a slot nor can be refused.
    static void EmitFree(Actor origin, String snd, int chan)
    {
        if (origin != null)
            origin.A_StartSound(snd, chan);
    }

    // PlaySoundLocActor / SD_PlaySound at the call sites.
    static void Emit(Actor origin, String snd, int chan = CHAN_AUTO,
                     double volume = 1.0, double attenuation = ATTN_NORM)
    {
        if (origin == null)
            return;
        WolfSnd s = WolfSnd.Get();
        if (s == null)
        {
            origin.A_StartSound(snd, chan, volume: volume,
                                attenuation: attenuation);
            return;
        }
        s.Gate(origin, snd, chan, volume, attenuation);
    }
}
