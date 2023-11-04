#!/bin/sh -e
mkdir -p build
nasm -fbin -o build/xfer.com xfer.asm
