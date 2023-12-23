#!/bin/sh -e
WATCOM="/opt/watcom"
OPTS="-0 -bt=dos -mc -i=${WATCOM}/h"
WASM="wasm ${OPTS} -zq"
WCC="wcc ${OPTS} -ot -zq -wx -zdp"
WLIB="wlib"
mkdir -p build
${WCC} sciplay.c -fo=build/sciplay.obj
${WCC} video.c -fo=build/video.obj
${WCC} sound.c -fo=build/sound.obj
${WCC} util.c -fo=build/util.obj
${WASM} timer.asm -fo=build/timer.obj
${WASM} driver.asm -fo=build/driver.obj
wlink option map system dos file build/sciplay.obj,build/timer.obj,build/driver.obj,build/sound.obj,build/video.obj,build/util.obj option eliminate name build/sciplay.exe
