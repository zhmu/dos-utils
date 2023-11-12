#!/bin/sh -e
WATCOM="/opt/watcom"
OPTS="-0 -bt=dos -mc -i=${WATCOM}/h"
WASM="wasm ${OPTS} -zq"
WCC="wcc ${OPTS} -ot -zq -wx"
WLIB="wlib"
mkdir -p build
${WCC} sciplay.c -fo=build/sciplay.obj
${WASM} timer.asm -fo=build/timer.obj
${WASM} driver.asm -fo=build/driver.obj
${WASM} serial.asm -fo=build/serial.obj
${WCC} sio.c -fo=build/sio.obj
wlink option map system dos file build/sciplay.obj,build/timer.obj,build/driver.obj,build/serial.obj,build/sio.obj option eliminate name build/sciplay.exe
