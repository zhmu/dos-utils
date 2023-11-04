#!/bin/sh -e
mkdir -p build
nasm -fbin -o build/boots.bin boots.asm
nasm -fbin -o build/instmbr.com instmbr.asm
