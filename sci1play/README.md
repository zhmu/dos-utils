# SCI1PLAY (Sierra Creative Interpreter 1) music player for DOS

Allow you to play SCI1 sound.nnn files on a DOS machine.

# Features

- Uses SCI1 drivers for playback
- Tested with ``adl.drv`` from Quest for Glory 3 English
- GPLv3 licensed

## Building

Simply run ``build.sh`` - you need to have [OpenWatcom](https://github.com/open-watcom/open-watcom-v2) (I used the [September 2023 snapshop of version 2.0](https://github.com/open-watcom/open-watcom-v2/releases/tag/2023-09-01-Build)) installed.

## Usage

You will need the original Sierra audio drivers (or patched versions thereof). Furthermore, the contents of the ``resource.*`` files must be extracted to obtain the necessary ``sound.*`` and ``patch.*`` files. This can be performed by using ``extract`` from my [sci-tools](https://github.com/zhmu/sci-tools/) repository (``cargo run --bin extract path_to_resource extract_path`` should do the trick)

Once all files are available, use ``sci1play sound.nnn`` - this will default to ``adl.drv`` and play the song.

Supported arguments:
- -v - increase verbosity
- -dfile.drv - use the supplied file as audio driver
- -pn - set playback volume to n (0..15)
- -s - enable serial mode

## Caveats / TODO

- The playback is likely not identical to that of SCI itself: feedback is most welcome (By email at rink@rink.nu or file an issue/pull request on GitHub)
- This only works with SCI1 games - SCI0 games use a different audio model which isn't supported by this code (use SCI0PLAY to play these)
- Serial port mode, similar to SCI0PLAY, needs to be implemented
- Lots of duplicated code from [SCI0PLAY](../sci0play/README.md)
