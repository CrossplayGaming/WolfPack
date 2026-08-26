// Wolf's sound priorities (ID_SD.C).
//
// Wolf does not mix. The Sound Blaster plays ONE digitized sound at a
// time and the AdLib chip ONE effect, so SD_PlaySound is a gate rather
// than a mixer: a new sound is REFUSED outright when its priority is
// below what that slot is already playing.
//
//     if (s->priority < DigiPriority)      // ID_SD.C:2169, digitized
//         return(false);                   // ID_SD.C:2185, AdLib
//
// That is why the original never sounds like it is stepping on itself.
// A door opening (priority 20) simply stays silent under a death cry
// (99); picking up treasure (70) does not truncate the machine gun's
// pickup (80). Equal priorities DO replace - that is deliberate, and
// it is what cuts Hitler's last line short when A_Slurpie fires twenty
// tics later (both 99).
//
// The slot frees itself when the sound ends (SDL_DigitizedDone,
// ID_SD.C:1184 - DigiNumber = DigiPriority = 0), which is what the end
// tic below stands in for.
//
// Priorities come from each AdLib chunk's header word and ship as
// wolfdata/sndprio.txt (tools/gen_sndpriority.py). Names missing from
// the table - the engine's own menu/* set - bypass the gate entirely.
//
// Wolf is one player at one place, so the two slots are GLOBAL, as they
// were in hardware. In a netgame that means a distant player's pickup
// can still hold the slot; the alternative is a per-listener mixer the
// original never had.

class WolfSnd : EventHandler
{
    const SLOTS = 2;            // 0 = digitized, 1 = AdLib
    // one engine channel per slot, so a replacement really replaces:
    // the previous emitter is silenced on the same channel first
    const CHAN_DIGI = CHAN_VOICE;
    const CHAN_ADLIB = CHAN_ITEM;

    Array<String> sndName;
    Array<int> sndPrio, sndSlot;
    bool tableLoaded;

    int slotPrio[SLOTS];
    int slotEnd[SLOTS];         // level.time the current sound finishes
    Actor slotFrom[SLOTS];      // who is emitting it

    static WolfSnd Get() { return WolfSnd(EventHandler.Find("WolfSnd")); }

    override void WorldLoaded(WorldEvent e)
    {
        LoadTable();
        for (int i = 0; i < SLOTS; i++)
        {
            slotPrio[i] = 0;
            slotEnd[i] = 0;
            slotFrom[i] = null;
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

    // SD_PlaySound (ID_SD.C:2126-2200) for one emitter.
    void Gate(Actor origin, String snd, int fallbackChan,
              double volume, double attenuation)
    {
        LoadTable();
        int i = Lookup(snd);
        if (i < 0)
        {
            origin.A_StartSound(snd, fallbackChan, volume: volume,
                                attenuation: attenuation);  // not a Wolf SFX
            return;
        }
        int slot = sndSlot[i];
        if (level.time >= slotEnd[slot])
            slotPrio[slot] = 0;                 // the slot has run dry
        if (sndPrio[i] < slotPrio[slot])
            return;                             // refused, never played
        int chan = slot == 0 ? CHAN_DIGI : CHAN_ADLIB;
        if (slotFrom[slot] != null && slotFrom[slot] != origin)
            slotFrom[slot].A_StopSound(chan);
        slotPrio[slot] = sndPrio[i];
        slotEnd[slot] = level.time + max(1, int(S_GetLength(snd) * 35.0));
        slotFrom[slot] = origin;
        origin.A_StartSound(snd, chan, volume: volume,
                            attenuation: attenuation);
    }

    // DELIBERATE DEVIATION - the melt plays ALONGSIDE the slot.
    //
    // A_Slurpie is the one place where Wolf's equal-priority replacement
    // costs the conversion something real. Hitler's last words (EVASND)
    // and the melt (SLURPIESND) are both priority 99 and both digitised,
    // and A_Slurpie fires from the action slot of s_hitlerdie3 - twenty
    // tics, 0.29s, into a two-second line. On one sound card the melt
    // simply took the channel and the line was cut; the Angel's death in
    // Spear has the same shape. We are not on one sound card, so the
    // melt gets a channel of its own and both are heard in full. It
    // neither takes the slot nor can be refused by it.
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
