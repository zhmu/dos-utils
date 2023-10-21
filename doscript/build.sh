#!/bin/sh -e
WATCOM="/opt/watcom"
OPTS="-0 -bt=dos -ms -i=${WATCOM}/h"
WASM="wasm ${OPTS} -zq"
WCC="wcc ${OPTS} -ot"
${WCC} doscript.c -fo=build/doscript.obj
${WASM} serial.asm -fo=build/serial.obj
wlink option map system dos file build/doscript.obj,build/serial.obj name build/doscript.exe

# create floppy image
dd if=/dev/zero of=floppy.img bs=512 count=2880
mformat -i floppy.img -f 1440 ::/
mcopy -oi floppy.img build/doscript.exe ::/d.exe
