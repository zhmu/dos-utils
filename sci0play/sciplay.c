#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <malloc.h>
#include <i86.h>
#include <conio.h>
#include <unistd.h>
#include <string.h>
#include "io.h"
#include "driver.h"
#include "sio.h"
#include "timer.h"

void far* driver_entry;

#define DEFAULT_DRIVER "adl.drv"
char* sound_driver = NULL;
int verbose = 0;
int serial_mode = 0;

uint8_t far* sound_data;

uint32_t timer_tick;

int playback_volume = 15;

#pragma pack(push, 1)
struct PATCH_RESOURCE {
    /* 00 */ char unknown[8];
    /* 08 */ uint16_t ptr_offset;
    /* 0a */ char far* data;
};

#define NO_PATCH 0xffff

#define SOUND_STATE_VALID 1
#define SOUND_STATE_INVALID 3

#define END_OF_TRACK 0xfc

struct SOUND_RESOURCE {
    /* 00 */ char unknown[8];
    /* 08 */ uint16_t ptr_offset;
    /* 0a */ uint16_t unk10;
    /* 0c */ uint16_t index; /* offset */
    /* 0e */ uint16_t unk4;
    /* 10 */ uint16_t state;
    /* 12 */ uint16_t unk18;
    /* 14 */ uint16_t unk20;
    /* 16 */ uint16_t signal;
    /* 18 */ uint16_t volume;
    char far* data;
};

struct SOUND_HEADER {
    uint8_t digital_sample_flag;
    uint16_t channel_info[16];
};
#pragma pack(pop)

struct PATCH_RESOURCE patch_res;
struct SOUND_RESOURCE sound_res;

char far* load_file(const char* fname, size_t extra_bytes, uint8_t extra_value)
{
    char far* buf = NULL;
    size_t size;

    FILE* f = fopen(fname, "rb");
    if (f == NULL) goto err;

    fseek(f, 0, SEEK_END);
    size = ftell(f);
    rewind(f);

    // Use halloc() as it guarantees the offset is 0; this is mainly important
    // for the audio driver which expects this
    buf = halloc(size + extra_value, 1);
    if (buf == NULL) goto err;

    if (!fread(buf, size, 1, f)) goto err;
    if (extra_bytes > 0) {
        memset(buf + size, extra_value, extra_bytes);
    }
    fclose(f);
    return buf;

err:
    if (buf != NULL) free(buf);
    fclose(f);
    return NULL;
}

static void reprogram_pit()
{
    /*
     * PIT frequency = 1193182Hz
     * Reload value = 19886
     * ==> Timer frequency = 1193182 / 19886 = 60Hz
     */
    const uint16_t reload_value = 19886;
    _disable();
    outb(0x43, 0x34); /* pit channel 0: mode 2 (rate generator), set lo/hi counter */
    outb(0x40, reload_value & 0xff);
    outb(0x40, reload_value >> 8);
    _enable();
}

int sound_init()
{
    struct SOUND_HEADER far* sh;
    int n;

    sh = (struct SOUND_HEADER far*)sound_data;
    if (verbose) {
        printf("digital_sample_flag %d\n", sh->digital_sample_flag);
        for(n = 0; n < 16; ++n) {
            printf("channel %d: nr voices %d, bitmask %x\n",
                n,
                (uint8_t)(sh->channel_info[n] >> 8),
                (uint8_t)(sh->channel_info[n] & 0xff));
        }
    }

    memset(&sound_res, 0, sizeof(sound_res));
    sound_res.ptr_offset = (uint16_t)&sound_res.data;
    sound_res.data = sound_data;
    sound_res.unknown[0] = 'S';
    sound_res.unknown[1] = 'N';
    sound_res.unknown[2] = 'D';
    sound_res.volume = playback_volume;

    _disable();
    timer_tick = 0;
    _enable();

    n = d_load_sound();
    if (n != SOUND_STATE_VALID) return 0;

    if (serial_mode) {
        sio_write('+'); // playback started
    }
    return 1;
}

static void help(const char* prog)
{
    printf("SCI0PLAY version 1.0 - (c) 2023 Rink Springer <rink@rink.nu>\n");
    printf("\n");
    printf("usage: %s [options] [-s | sound.nnn ...]\n\n", prog);
    printf("options can be:\n");
    printf("  -h, -help   this help\n");
    printf("  -v          verbose\n");
    printf("  -s          enable serial mode\n");
    printf("  -dfile.drv  use file.drv as audio driver (default: %s)\n", DEFAULT_DRIVER);
    printf("  -pn         set playback volume to n (0..15)\n");
    printf("\n");
}

static int parse_args(int argc, char* argv[])
{
    int n;
    for(n = 1; n < argc; ++n) {
        if (argv[n][0] != '-') break;

        if (strcmp(argv[n]+1, "h") == 0 || strcmp(argv[n]+1, "help") == 0) {
            help(argv[0]);
            return 0;
        }
        if (strcmp(argv[n]+1, "v") == 0) {
            ++verbose;
            continue;
        }
        if (strcmp(argv[n]+1, "s") == 0) {
            ++serial_mode;
            continue;
        }
        if (argv[n][1] == 'd') {
            sound_driver = argv[n]+2;
            continue;
        }
        if (argv[n][1] == 'p') {
            playback_volume = atoi(argv[n]+2);
            if (playback_volume < 0) playback_volume = 0;
            if (playback_volume > 15) playback_volume = 15;
            continue;
        }

        printf("unrecognized commandline argument - use -h / -help for help\n");
        return 0;
    }

    if (sound_driver == NULL) {
        printf("no sound driver specified, defaulting to '%s'...\n", DEFAULT_DRIVER);
        sound_driver = DEFAULT_DRIVER;
    }
    return n;
}

static char* tick_format(char* out, uint32_t ticks)
{
    int sec, ms, min;
    sec = ticks / 60;
    ms = (ticks % 60) * 16;
    if (sec >= 60) {
        min = sec / 60;
        sec = sec % 60;
        sprintf(out, "%02d:%02d.%03d", min, sec, ms);
    } else {
        sprintf(out, "%02d.%03d", sec, ms);
    }
    return out;
}

static int play_file(const char* fname)
{
    uint16_t prev_index;
    uint32_t prev_timer_tick;
    char tick_str[32];

    /*
     * Make sure the sound data ends with END_OF_TRACK commands to stop the
     * playback - otherwise it'd play random junk.
     */
    sound_data = load_file(fname, 4, END_OF_TRACK);
    if (sound_data == NULL) {
        printf("unable to load sound '%s'\n", sound);
        return -1;
    }

    printf("- Initializing sound...");
    if (!sound_init()) {
        hfree(sound_data);
        printf(" failure!\n");
        return -1;
    }

    prev_index = 0;
    prev_timer_tick = timer_tick;
    while (!kbhit() && sound_res.signal != 0xffff) {
        if (prev_timer_tick == timer_tick)
            continue;
        tick_format(tick_str, timer_tick);

        if (verbose) {
            printf("Playing %s (%ld): index %d state %d volume %d     \r",
                tick_str,
                timer_tick,
                sound_res.index,
                sound_res.state,
                sound_res.volume);
        } else {
            printf("Playing %s     \r",
                tick_str);
        }
        if (prev_index > sound_res.index) {
            printf("loop detected, bye\n");
            break;
        }
        prev_index = sound_res.index;
        prev_timer_tick = timer_tick;
    }

    d_stop_sound();
    hfree(sound_data);
    return 1;
}

static int handshake()
{
    unsigned char cmd;
    while(1) {
        if (kbhit()) {
            printf("< aborted!\n");
            return 0;
        }
        if (sio_char_ready()) {
            cmd = sio_read();
            if (cmd == '!') {
                printf("< OK\n");
                break;
            }
            if (cmd == '#') {
                continue;
            }
        }
        sio_write('?');
        delay(1000);
    }
    return 1;
}

static int do_serial()
{
    char s[64];
    int n;
    unsigned char cmd;

    sio_setup();

    printf("> Waiting for handshake...\n");
    if (!handshake()) return 1;

    timer_hook();
    atexit(timer_unhook);
    reprogram_pit();

    while(1) {
        int running = 1;
        printf("> Waiting for command...\n");
        while(running && !sio_char_ready()) {
            if (kbhit()) running = 0;
        }
        if (!running) break;

        cmd = sio_read();
        switch(cmd) {
            case 'P': // play
                n = sio_get_string(s, sizeof(s));
                if (n <= 0) {
                    sio_write('-');
                    continue;
                }
                if (access(s, R_OK) != 0) {
                    sio_write('N'); // N = file not found
                    continue;
                }
                if(play_file(s)) {
                    sio_write('R'); // ready
                } else {
                    printf("p, ERROR\n");
                }
                break;
            default:
                printf("? Unrecognized command '%c', aborting\n", cmd);
                return 0;
        }
    }
    return 0;
}

static int load_audio_driver(const char* fname)
{
    void far* patch_data = NULL;
    struct DRIVER_INFO di;
    char s[32];

    driver_entry = load_file(fname, 0, 0);
    if (driver_entry == NULL) {
        printf("unable to load audio driver '%s'\n", sound_driver);
        return 0;
    }

    if (!driver_info(&di)) {
        printf("unable to obtain driver info - is this a SCI0 audio driver?\n");
        return 0;
    }
    if (di.patch_nr != NO_PATCH && di.patch_nr >= 0x100) {
        printf("driver requests patch %u - this is likely a SCI1 audio driver, will not continue\n", di.patch_nr);
        return 0;
    }

    if (verbose) {
        printf("%s: number of voices %d\n", sound_driver, di.nr_voices);
    }

    memset(&patch_res, 0, sizeof(patch_res));
    if (di.patch_nr != NO_PATCH) {
        sprintf(s, "patch.%03d", di.patch_nr);
        if (verbose) {
            printf("driver requests contents of %s, loading...\n", s);
        }
        patch_data = load_file(s, 0, 0);
        if (patch_data == NULL) {
            printf("unable to load %s\n", s);
            return 0;
        }
        patch_res.ptr_offset = (uint16_t)&patch_res.data;
        patch_res.data = patch_data;
    }

    return 1;
}

int main(int argc, char* argv[])
{
    int n, next_arg;

    if (argc < 2) {
        help(argv[0]);
        return 1;
    }

    next_arg = parse_args(argc, argv);
    if (!next_arg) {
        return 1;
    }

    if (!load_audio_driver(sound_driver)) {
        return 1;
    }
    if (!d_init()) {
        printf("unable to initialize sound driver\n");
        return -1;
    }
    atexit(d_terminate);

    if (serial_mode) {
        do_serial();
    } else {
        timer_hook();
        atexit(timer_unhook);
        reprogram_pit();

        for(n = next_arg; n < argc; ++n) {
            play_file(argv[n]);
        }
    }
    return 0;
}
