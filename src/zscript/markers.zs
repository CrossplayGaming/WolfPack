// Invisible sim-data markers carried as things by the converter.
// Turn points (map codes 90-97, MAP-016) feed patrol pathing in the enemy
// pass; the victory trigger (code 99, MAP-017) fires the episode-end
// sequence in the progression pass. For now they exist, are invisible,
// and are discoverable by tile.
class WolfMarker : Actor abstract
{
    int tileX, tileY;
    Default
    {
        +NOBLOCKMAP +NOSECTOR +NOINTERACTION +NOGRAVITY +INVISIBLE
    }
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        tileX = int(pos.x) / 64;
        tileY = 63 - (int(pos.y) / 64);
    }
}

class WolfTurnE  : WolfMarker {}
class WolfTurnNE : WolfMarker {}
class WolfTurnN  : WolfMarker {}
class WolfTurnNW : WolfMarker {}
class WolfTurnW  : WolfMarker {}
class WolfTurnSW : WolfMarker {}
class WolfTurnS  : WolfMarker {}
class WolfTurnSE : WolfMarker {}
class WolfVictoryTrigger : WolfMarker {}
