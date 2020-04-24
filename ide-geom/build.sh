#!/bin/sh -e
nasm -fbin -o boots.bin boots.asm
nasm -fbin -o install.com install.asm
dd if=/dev/zero of=floppy.img bs=512 count=2880
mformat -i floppy.img -f 1440 ::/
mcopy -oi floppy.img boots.bin ::/boots.bin
mcopy -oi floppy.img install.com ::/install.com
