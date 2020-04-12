#!/bin/sh -e
nasm -fbin -o xfer.com xfer.asm
dd if=/dev/zero of=floppy.img bs=512 count=2880
mformat -i floppy.img -f 1440 ::/
mcopy -oi floppy.img xfer.com ::/x.com
