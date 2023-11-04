# VGM (Video Game Music) player for DOS

Allow you to conveniently play VGM/VGZ files on DOS machine. This utility can be considered as an alternative to the more established [SBVGM](http://www.oplx.com/code/) utility.

# Features

- Transparant support for VGZ (zlib-compressed VGM) files
- Supported hardware: Adlib, SoundBlaster (both OPL2 and OPL3-based), OPL2LPT, OPL3LPT
- GPLv3 licensed

## Building

Simply run ``build.sh`` - you need to have [OpenWatcom](https://github.com/open-watcom/open-watcom-v2) (I used the [September 2023 snapshop of version 2.0](https://github.com/open-watcom/open-watcom-v2/releases/tag/2023-09-01-Build)) and mtools installed.

The output is a 1.44MB floppy disk image, ``floppy.img``, which contains a ``dosvgm.exe``.

## Usage

Basic use is ``dosvgm file`` - this will attemp to locate a Sound Blaster (or compatible) device and play the supplied file.

Supported arguments:
- -a - use an Adlib sound card
- -sb - use a SoundBlaster sound card (OPL2/OPL3 will be auto-detected based on DSP version)
- -opl2lpt - use an OPL2LPT card attached to the first parallel port
- -opl3lpt - use an OPL3LPT card attached to the first parallel port

## Caveats / TODO

- OPL3 chips aren't properly reset once playback ends, possible resulting in hanging notes
- Using the Pentium's TSC could yield extra timing accuracy, if available
- OPL2LPT/OPL3LPT shouldn't be hardcoded to the first parallel port
- Looping is not supported
- Replacing stock ZLIB with a more space-optimised implementation could be beneficial