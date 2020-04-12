#!/bin/sh -e
nasm -fbin -o nfspkt.com nfspkt.asm
dd if=/dev/zero of=floppy.img bs=512 count=2880
mformat -i floppy.img -f 1440 ::/
mcopy -oi floppy.img nfspkt.com ::/n.com
