# Simple serial file transfer utility

A simply tool to transfer files from your development machine to your retro machine over RS-232.

## Building
Simply run ``build.sh`` - you need to have nasm installed. The resulting binary is available ``build/xfer.com``.

## Usage
- Set up a null-modem cable (only RXD/TXD/GND are needed) between the development and legacy machines
- On the legacy system: execute ``X.COM filename.txt`` (to store the received data to filename.txt)
- On the development system: run ``./pyxfer.py file.txt`` (to send data from file.txt)

## Options
The source code has some knobs you can tweak, with their current defaults:

- COM_BASE = 3f8h: I/O address of the serial port to use (default is COM1)

## Caveats / TODO

- The checksum algorithm is complete bogus
- Custom flow control
- Sending data in chunks and checksumming them separately might be a good idea
- How are you initially going to transfer this utility?
