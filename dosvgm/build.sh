#!/bin/sh -e
WATCOM="/opt/watcom"
OPTS="-0 -bt=dos -ml -i=${WATCOM}/h -i=zlib-1.3"
WASM="wasm ${OPTS} -DNO_GZCOMPRESS -zq"
WCC="wcc ${OPTS} -ot -zq -wx"
WLIB="wlib"
mkdir -p build build/zlib
${WCC} dosvgm.c -fo=build/dosvgm.obj
${WCC} buffer.c -fo=build/buffer.obj
${WCC} adlib.c -fo=build/adlib.obj
${WCC} sb.c -fo=build/sb.obj
${WCC} opl_lpt.c -fo=build/opl_lpt.obj
if [ ! -f build/zlib.lib ]; then
    ${WCC} zlib-1.3/adler32.c -fo=build/zlib/adler32.obj
    ${WCC} zlib-1.3/compress.c -fo=build/zlib/compress.obj
    ${WCC} zlib-1.3/crc32.c -fo=build/zlib/crc32.obj
    ${WCC} zlib-1.3/deflate.c -fo=build/zlib/deflate.obj
    ${WCC} zlib-1.3/gzclose.c -fo=build/zlib/gzclose.obj
    ${WCC} zlib-1.3/gzlib.c -fo=build/zlib/gzlib.obj
    ${WCC} zlib-1.3/gzread.c -fo=build/zlib/gzread.obj
    ${WCC} zlib-1.3/gzwrite.c -fo=build/zlib/gzwrite.obj
    ${WCC} zlib-1.3/infback.c -fo=build/zlib/infback.obj
    ${WCC} zlib-1.3/inffast.c -fo=build/zlib/inffast.obj
    ${WCC} zlib-1.3/inflate.c -fo=build/zlib/inflate.obj
    ${WCC} zlib-1.3/inftrees.c -fo=build/zlib/inftrees.obj
    ${WCC} zlib-1.3/trees.c -fo=build/zlib/trees.obj
    ${WCC} zlib-1.3/uncompr.c -fo=build/zlib/uncompr.obj
    ${WCC} zlib-1.3/zutil.c -fo=build/zlib/zutil.obj
    ${WLIB} build/zlib.lib -+build/zlib/adler32.obj -+build/zlib/compress.obj -+build/zlib/crc32.obj -+build/zlib/deflate.obj -+build/zlib/gzclose.obj -+build/zlib/gzlib.obj -+build/zlib/gzread.obj -+build/zlib/gzwrite.obj -+build/zlib/infback.obj -+build/zlib/inffast.obj -+build/zlib/inflate.obj -+build/zlib/inftrees.obj -+build/zlib/trees.obj -+build/zlib/uncompr.obj -+build/zlib/zutil.obj
fi
${WASM} timer.asm -fo=build/timer.obj
wlink option map system dos file build/dosvgm.obj,build/timer.obj,build/buffer.obj,build/adlib.obj,build/sb.obj,build/opl_lpt.obj,build/zlib.lib option eliminate name build/dosvgm.exe

# create floppy image
dd if=/dev/zero of=floppy.img bs=512 count=2880
mformat -i floppy.img -f 1440 ::/
mcopy -oi floppy.img build/dosvgm.exe ::/dosvgm.exe
