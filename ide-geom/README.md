# IDE geometry override

This is a bootsector-based utility which will query the first IDE device for the geometry (cylinders/heads/sectors) and place these values in the BIOS. This allows a more modern IDE device, such as a CompactFlash card, to be used with a BIOS that does not allow you to specify a custom drive type.

## Building
Simply run ``build.sh`` - you need to have nasm installed. The ``build`` folder contains the bootsector binary ``boots.bin`` and an installation utility ``instmbr.com``.

## Usage
Execute ``instmbr.com`` (it needs to have ``boots.bin`` in the current directory). It prints ``B`` on success or ``E`` on failure. Upon boot from disk, a banner will show device name and overriden disk geometry.

If you hold the shift key during boot, the harddisk boot will be skipped and the first floppy device is used instead. This is useful for new installations, when the harddisk is not properly set up yet but you need the correct geometry to be set up.

## Caveats / TODO

The entire disk is usable on my tests, however there are some caveats:

- MS-DOS 6.22's SCANDISK does not want to verify the disk once patched
- MS-DOS 6.22's CHKDSK reports problems

Analysis or Patches are most welcome and can be sent to rink@rink.nu.
