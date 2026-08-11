// Level music ownership.
//
// User report: the menu song (WONDERIN) keeps playing over a level that
// was LOADED FROM A SAVE; going to the menu and coming back fixes it.
// The menu starts WONDERIN itself and only BackOut puts the level song
// back - a path a save load never takes.
//
// The first fix put the reclaim in WolfLevel.WorldLoaded, which is
// wrong: measured with a probe (build/xhair/mus4.txt), a plain
// EventHandler gets NO WorldLoaded when a savegame is loaded, while a
// StaticEventHandler gets one with IsSaveGame true. PlayerEntered does
// not fire on a save load either. So the claim lives here, in a static
// handler, which is the only one of the three the save path reaches.
class WolfMusic : StaticEventHandler
{
    // re-assert a few tics later in case the engine's own restore of
    // the saved music state lands after WorldLoaded
    int musicFix;

    override void WorldLoaded(WorldEvent e)
    {
        musicFix = 0;
        Claim();
    }

    override void WorldTick()
    {
        if (musicFix > 0 && --musicFix == 0)
            Claim(false);
    }

    // force: true. Without it S_ChangeMusic no-ops when the engine
    // already BELIEVES this track is current - exactly the state a save
    // load restores, while the menu song is what is actually coming out
    // of the speakers.
    private void Claim(bool arm = true)
    {
        if (Level.MapName == "TITLEMAP" || Level.Music == "")
            return;
        bool started = S_ChangeMusic(Level.Music, Level.musicorder,
                                     true, true);
        if (arm)
            musicFix = 5;
        CVar mv = CVar.FindCVar("wolf_dbg_check");
        if (mv != null && mv.GetInt() != 0)
            Console.Printf("MUSIC %s started=%d", Level.Music, started);
    }
}
