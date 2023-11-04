#!/bin/sh -e
mkdir -p build
nasm -fbin -o build/gdbstub.com gdbstub.asm
