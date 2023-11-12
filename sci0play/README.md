# SCI0PLAY (Sierra Creative Interpreter 0) music player for DOS

Allow you to play SCI0 sound.nnn files on a DOS machine. There is also support for scripting over a serial port for automated music archival.

# Features

- Uses SCI0 drivers for playback
- Tested with ``adl.drv`` and ``mt32.drv`` from Quest for Glory 1 EGA, Police Quest 2, Space Quest 3, Colonel's Bequest, King's Quest 4
- Using ADLPATCH to patch ``adl.drv`` for OPL2LPT works except on Space Quest 3 (doesn't recognise the driver)
- GPLv3 licensed

## Building

Simply run ``build.sh`` - you need to have [OpenWatcom](https://github.com/open-watcom/open-watcom-v2) (I used the [September 2023 snapshop of version 2.0](https://github.com/open-watcom/open-watcom-v2/releases/tag/2023-09-01-Build)) installed.

## Usage

You will need the original Sierra audio drivers (or patched versions thereof). Furthermore, the contents of the ``resource.*`` files must be extracted to obtain the necessary ``sound.*`` and ``patch.*`` files. This can be performed by using ``extract`` from my [sci-tools](https://github.com/zhmu/sci-tools/) repository (``cargo run --bin extract path_to_resource extract_path`` should do the trick)

Once all files are available, use ``sci0play sound.nnn`` - this will default to ``adl.drv`` and play the song.

Supported arguments:
- -v - increase verbosity
- -dfile.drv - use the supplied file as audio driver
- -pn - set playback volume to n (0..15)
- -s - enable serial mode

## Serial mode

The ``-s`` flag causes filenames to be ignored. The player will listen on COM2 (115200/8N1) for a handshake and accept a command to play files. This is useful for automated archiving of music. Refer to ``sciplay.c`` for details.

## Caveats / TODO

- This only works with SCI0 games - SCI1 games use a different audio model which isn't supported by this code
- Serial mode is poorly documented, I should clean up and release my scripts that interface with it
- Lots of duplicated code from [DOScript](../doscript/README.md)