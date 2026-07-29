# Put your game data here

WolfPack builds from **your own copies** of the games. Both games share
this one folder — their files use different extensions, so nothing
collides.

## Wolfenstein 3D (required)

    AUDIOHED.WL6  AUDIOT.WL6  GAMEMAPS.WL6  MAPHEAD.WL6
    VGADICT.WL6   VGAGRAPH.WL6  VGAHEAD.WL6  VSWAP.WL6

## Spear of Destiny (optional)

Add these and the 21-floor Spear campaign gets built too, as its own
`spear.ipk3`. Leave them out and you simply get Wolfenstein 3D.

    AUDIOHED.SOD  AUDIOT.SOD  GAMEMAPS.SOD  MAPHEAD.SOD
    VGADICT.SOD   VGAGRAPH.SOD  VGAHEAD.SOD  VSWAP.SOD

They can sit here alongside the WL6 files, or in an `m1` subfolder
(`gamedata/m1/`) if you prefer to mirror how Steam ships them.

## Where to find them

- **Steam**: `steamapps/common/Wolfenstein 3D/base/` holds the WL6
  files and `base/m1/` holds Spear. If you have the Steam version
  installed you can skip this folder entirely — the build finds it
  automatically, both games included.
- **GOG / original discs**: the games' install directories.

The registered (not shareware) Wolfenstein 3D is required. No game data
is ever committed to or distributed with this repository.
