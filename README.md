# DOS utilities

This is a collection of MS-DOS/FreeDOS-based utilities, which may be useful for others who are interested in retro (legacy) systems. All of these tools are licensed using GNU General Public License v3.0.

If you found any of these utilities useful, please let me know at rink@rink.nu !

## GDB debugging stub

A small TSR which provides interfacing to the GNU Debugger using the remote serial port debugging protocol. You can place INT3 breakpoints throughout your code and inspect/step/continue execution from GDB.

## Simple RS-232 transfer utility

Trivial utility to transfer files from your development machine to your target machine. Uses RS-232 with checksums.

## NFSv3 client for DOS

TSR that allows you to map a NFSv3 server over IPv4 to a DOS drive letter.

## IDE geometry override bootsector

Custom bootsector that queries the first IDE device for the disk geometry and programs this in the BIOS. Useful when using CompactFlash cards on old systems that do not support custom disk geometries.

## DOScript

Allows you to control your DOS-based machine over a serial connection, useful for scripting purposes.

## DOSVGM

DOS-based Video Game Music (VGM) player for VGM/VGZ files. Supports Adlib, Sound Blaster and OPL2LPT/OPL3LPT output devices.