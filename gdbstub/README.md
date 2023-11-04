# DOS-based GNU debugger stub

This will allow you to use the GNU debugger's remote debugging capabilities to debug your retro project using a serial port. The stub is intended for 16 bit real-mode applications on an XT or up.

## Building
Simply run ``build.sh`` - you need to have nasm and mtools installed.

The output is a 1.44MB floppy disk image, ``floppy.img``, which contains a ``g.com`` which is the GDB stub.

## Usage
Run ``g.com`` to install the TSR (again to uninstall).

The TSR will intercept INT3 instructions; upon encountering, execution will be suspended and the GDB debugging protocol will be used.

## GDB setup
Place the following in your .gdbinit:

```
set architecture i8086
set disassembly-flavor intel
display/i ($cs<<4)+$pc
target remote /dev/ttyUSB0
```

Remember that the stub will always use linear addresses, so you'll need to use ``x/b ($ds<<4)+$si`` to examine the byte at DS:SI, for example.

## Options
The source code has some knobs you can tweak, with their current defaults:

- GDB_TRACE = 0: if non-zero, all GDB packets received/sent will be logged on the screen
- SHOW_MARKER = 1: if non-zero, a G character will be shown in the top-right if GDB stub is active
- BREAK = 0: if non-zero, the scan-code of the key to break to the debugger (experimental, not very stable!)

## Caveats / TODO

- Only 16 bit registers are used
- Protected mode is not supported
- Initiating a break from GDB is not supported (needs serial interrupts)
