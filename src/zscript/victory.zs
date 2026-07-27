// BJ's victory run (SpawnBJVictory / T_BJRun / T_BJJump / T_BJYell /
// T_BJDone, WL_ACT2.C:3596-3712).
//
// Confirmed from the map data, not memory: only the two floors whose boss
// has NO DeathCam carry victory-trigger tiles — E1 (Hans, 3 tiles) and E5
// (Gretel, 6). The DeathCam bosses (Schabbs E2, Hitler E3, Gift E4, Fat
// E6) end their episode through the replay instead, and their floors have
// zero victory tiles. The two endings are complementary, never both.
//
// The run: BJ spawns one tile south of the player facing north, sprints
// 6 tiles at BJRUNSPEED (2048), then jumps at BJJUMPSPEED (680), yelling
// on the second jump frame, and the last frame ends the episode.
class WolfBJVictory : Actor
{
    const BJRUNSPEED = 2048;
    const BJJUMPSPEED = 680;

    int wolfX, wolfY;
    int tileX, tileY;
    int tilesLeft;          // temp1: tiles to run forward
    int distance;
    int phase;              // 0 running, 1 jumping
    int seq, seqTics;

    Default
    {
        +NOBLOCKMAP +NOGRAVITY +NOINTERACTION +DONTSPLASH;
        Radius 8;
        Height 64;
    }

    // s_bjrun1..4 (12/3/8/12/3/8 tics) then s_bjjump1..4 (14/14/14/300)
    static const int RUNTICS[] = { 12, 3, 8, 12, 3, 8 };
    static const int RUNFRAME[] = { 0, 0, 1, 2, 2, 3 };
    static const int JUMPTICS[] = { 14, 14, 14, 300 };
    static const int JUMPFRAME[] = { 0, 1, 2, 3 };

    void StartRun(Actor player)
    {
        // SpawnBJVictory: one tile SOUTH of the player, facing north, so he
        // sprints up past the camera before jumping at it.
        tileX = int(player.pos.x) / 64;
        tileY = 63 - (int(player.pos.y) / 64) + 1;
        wolfX = int(player.pos.x * 1024);
        wolfY = int((4096.0 - player.pos.y) * 1024) + 0x10000;
        tilesLeft = 6;
        distance = 0x10000;
        seq = 0;
        seqTics = RUNTICS[0];
        sprite = GetSpriteIndex("BJRN");
        frame = 0;
        SetOrigin((wolfX / 1024.0, 4096.0 - wolfY / 1024.0, pos.z), false);
    }

    override void Tick()
    {
        if (IsFrozen())
            return;
        // animation
        seqTics -= 2;
        if (seqTics <= 0)
        {
            if (phase == 0)
            {
                seq = (seq + 1) % 6;
                seqTics = RUNTICS[seq];
                frame = RUNFRAME[seq];
            }
            else
            {
                if (seq < 3)
                {
                    seq++;
                    seqTics = JUMPTICS[seq];
                    frame = JUMPFRAME[seq];
                    if (seq == 1)
                        A_StartSound("wolf/yeah", CHAN_VOICE);  // T_BJYell
                    if (seq == 3)
                        Finish();
                }
            }
        }

        int move = (phase == 0 ? BJRUNSPEED : BJJUMPSPEED) * 2;
        while (move > 0)
        {
            if (move < distance)
            {
                wolfY -= move;      // running north
                distance -= move;
                break;
            }
            wolfY -= distance;
            move -= distance;
            tileY--;
            distance = 0x10000;
            if (phase == 0 && --tilesLeft <= 0)
            {
                phase = 1;          // s_bjjump1
                seq = 0;
                seqTics = JUMPTICS[0];
                sprite = GetSpriteIndex("BJJP");
                frame = 0;
                break;
            }
        }
        SetOrigin((wolfX / 1024.0, 4096.0 - wolfY / 1024.0, 0), true);

        CVar dv = CVar.FindCVar("wolf_dbg_victory");
        if (dv != null && dv.GetInt() != 0 && (level.maptime % 5) == 0)
            Console.Printf("WOLFDBG bj: t=%d tile=%d,%d phase=%d left=%d "
                           "spr=%d frame=%d", level.maptime, tileX, tileY,
                           phase, tilesLeft, sprite, frame);
    }

    // T_BJDone: playstate = ex_victorious
    void Finish()
    {
        // TODO: episode-end text screens; for now the floor simply ends
        Level.ExitLevel(0, false);
        Destroy();
    }

    States
    {
    SpriteRegistry:
        BJRN ABCD -1;
        BJJP ABCD -1;
        Stop;
    }
}
