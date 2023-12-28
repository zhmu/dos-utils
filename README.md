# DOS utilities

This is a collection of MS-DOS/FreeDOS-based utilities, which may be useful for others who are interested in retro (legacy) systems. All of these tools are licensed using GNU General Public License v3.0.

If you found any of these utilities useful, please let me know at rink@rink.nu !

* [GDB debugging stub](gdbstub/README.md): TSR allowing GDB to interface with your DOS-based machine using a serial port
* [Simple RS-232 transfer utility](xfer/README.md): trivial utility to transfer files from your development machine to your target machine. Uses RS-232 with checksums
* [NFSv3 client](nfs/README.md): TSR that allows you to map a NFSv3 server over IPv4 to a DOS drive letter
* [IDE geometry override bootsector](ide-geom/README.md): custom bootsector to override the bios CHS settings with the drive's
* [DOScript](doscript/README.md): allows you to control your DOS-based machine over a serial connection (intended for scripting purposes)
* [DOSVGM](dosvgm/README.md): DOS-based Video Game Music (VGM) player for VGM/VGZ files. Supports Adlib, Sound Blaster and OPL2LPT/OPL3LPT output devices.

## Prerequisites

You need to install nasm, mtools and [OpenWatcom](https://github.com/open-watcom/open-watcom-v2) (I used the [September 2023 snapshop of version 2.0](https://github.com/open-watcom/open-watcom-v2/releases/tag/2023-09-01-Build)).

## Building

All utilities have a ``build.sh`` in their respective directories. The ``build.sh`` in the repository root directory will build all utilities and create ``utils.img`` which is a 1.44MB floppy disk image containing all utilities.
