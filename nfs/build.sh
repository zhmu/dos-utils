#!/bin/sh -e

# use small memory model (code/data in same 64kb segment)
MODEL=s
COMMON="-0 -bt=dos -m${MODEL}"
WASM="wasm ${COMMON} -q"

# build this stuff
${WASM} dhcp.asm -fo=build/dhcp.obj
${WASM} resident.asm -fo=build/resident.obj
${WASM} helper.asm -fo=build/helper.obj
${WASM} main.asm -fo=build/main.obj
${WASM} net.asm -fo=build/net.obj
${WASM} nfs.asm -fo=build/nfs.obj
${WASM} print.asm -fo=build/print.obj
${WASM} redir.asm -fo=build/redir.obj
${WASM} rpc.asm -fo=build/rpc.obj
${WASM} res_end.asm -fo=build/res_end.obj
${WASM} helper2.asm -fo=build/helper2.obj
${WASM} net2.asm -fo=build/net2.obj
${WASM} redir2.asm -fo=build/redir2.obj
(cd build && wlink @../build.lnk)
