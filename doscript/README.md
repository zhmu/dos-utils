# DOScript

This allows you to control your DOS-based machine using a serial connection.

# Features

- Transfer files from host to DOS-machine
- Remove files on the DOS-machine
- Execution of commands

# Building

Simply run ``build.sh`` - you need to have [OpenWatcom](https://github.com/open-watcom/open-watcom-v2) (I used the [September 2023 snapshop of version 2.0](https://github.com/open-watcom/open-watcom-v2/releases/tag/2023-09-01-Build)) and mtools installed.

The output is a 1.44MB floppy disk image, ``floppy.img``, which contains a ``d.exe`` which is the DOScript utility.

## Usage

Simply build the executable and run it on your target system. The ``python`` directory contains a client library and example Python script to interact with the DOS machine.

## Development

You can use QEMU to test this code; use ``mkfifo /tmp/serial.in /tmp/serial.out`` to create named FIFO's to emulate the serial port and invoke QEMU using ``-serial pipe:/tmp/serial`` to connect to the FIFO. The Python client code can be configured to use the FIFO instead of a serial port.

## Caveats

- The code is hardcoded to COM2, 115200/8N1. This should be configurable
- Corrupted chunks when sending files are properly detected, but retries aren't implemented
- Random hangs when executing a program (maybe the ISR code is buggy? Need to look into this...)
