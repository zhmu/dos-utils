#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <i86.h>
#include <conio.h>
#include <string.h>
#include "io.h"
#include "driver.h"
#include "midi.h"
#include "sound.h"
#include "timer.h"
#include "util.h"
#include "video.h"

void far* driver_entry;

#define DEFAULT_DRIVER "adl.drv"
char* sound_driver = NULL;
void far* patch_data = NULL;

uint32_t timer_tick;
static int verbose = 0;
static int loop = 0;
static int playback_volume = 15;

static struct DRIVER_INFO drv_info;
static uint8_t hiChnl, loChnl;

#define VPRINTF(v, ...) \
    if (verbose >= (v)) \
        printf(__VA_ARGS__)

#define NO_PATCH 0xffff

static int load_audio_driver(const char* fname)
{
    char s[32];

    driver_entry = load_file(fname);
    if (driver_entry == NULL) {
        printf("unable to load audio driver '%s'\n", fname);
        return 0;
    }

    if (!driver_info(&drv_info)) {
        printf("unable to obtain driver info - is this a SCI1 audio driver?\n");
        return 0;
    }
    if (drv_info.patch_nr != NO_PATCH && drv_info.patch_nr < 0x100) {
        printf("driver requests patch %u - this is likely a SCI0 audio driver, will not continue\n", drv_info.patch_nr);
        return 0;
    }

    VPRINTF(1, "%s: number of voices %d\n", fname, drv_info.nr_voices);

    if (drv_info.patch_nr != NO_PATCH) {
        sprintf(s, "patch.%03d", drv_info.patch_nr & 0xff);
        VPRINTF(1, "driver requests contents of %s, loading...\n", s);
        patch_data = load_file(s);
        if (patch_data == NULL) {
            printf("unable to load %s\n", s);
            return 0;
        }
    }

    return 1;
}

static int count_active_ch()
{
    int count = 0;
    int n;

    for(n = 0; n < MAX_TRACKS; ++n) {
        if (track_info[n].offset == 0) continue;
        ++count;
    }
    return count;
}

static void format_tick(char* out, uint32_t ticks)
{
    // Ticks are at 60Hz, hence 1 tick is 1/60 = 16.67ms.
    int sec, min;
    uint32_t ms;
    sec = ticks / 60;
    // Every tick is 16.67ms
    ms = (ticks % 60) * 1667;
    ms /= 100;
    if (sec >= 60) {
        min = sec / 60;
        sec = sec % 60;
        sprintf(out, "%02d:%02d.%03d", min, sec, ms);
    } else {
        sprintf(out, "%02d.%03d", sec, ms);
    }
}

static void update_screen(const char* path)
{
    int n = 0;
    uint8_t attr;
    char s[80];
    struct TRACK_INFO* ti;

    vputs(0, 0, ATTR_WHITE, path);
    vputs(strlen(path), 0, ATTR_GREY, ":");
    format_tick(s, timer_tick);
    vputs(strlen(path) + 2, 0, ATTR_YELLOW, s);

    for(n = 1; n <= MAX_TRACKS; ++n) {
        ti = &track_info[n - 1];
        attr = ATTR_GREEN;
        if (ti->offset == 0) {
            attr = ATTR_RED;
        }
        sprintf(s, "%2d", n);
        vputs(0, n, attr, s);
        vputs(2, n, attr, ":");
        if (ti->cur_note != 255) {
            sprintf(s, ": %d    ", ti->cur_note);
        } else {
            sprintf(s, ": ---   ");
        }
        vputs(4, n, attr, s);
    }
}

static void help(const char* prog)
{
    printf("SCI1PLAY version 1.0 - (c) 2023 Rink Springer <rink@rink.nu>\n");
    printf("https://github.com/zhmu/dos-utils/tree/master/sci1play\n");
    printf("\n");
    printf("usage: %s [options] sound.nnn ...\n", prog);
    printf("options can be:\n");
    printf("  -h, -help   this help\n");
    printf("  -v          verbose\n");
    printf("  -l          loop sound (plays forever)\n");
    printf("  -dfile.drv  use file.drv as audio driver (default: %s)\n", DEFAULT_DRIVER);
    printf("  -pn         set playback volume to n (0..15, default: %d)\n", playback_volume);
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
        if (strcmp(argv[n]+1, "l") == 0) {
            ++loop;
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

static int play_file_ui(const char* path)
{
    uint32_t prev_timer_tick;

    if (!sound_load(path)) {
        printf("cannot load '%s'\n", path);
        return 0;
    }
    if (!sound_init(drv_info.device_id)) {
        printf("cannot initialize sound (can it be played on this hardware?)\n");
        return 0;
    }

    d_set_volume(playback_volume);

    prev_timer_tick = timer_tick;
    while (!kbhit()) {
        if (prev_timer_tick == timer_tick)
            continue;

        if (count_active_ch() == 0) {
            if (loop) {
                printf("looping sound\n");
                sound_loop();
            } else {
                printf("all channels finished, stopping...\n");
                break;
            }
        }

        sound_server();
        d_service();
        update_screen(path);
        prev_timer_tick = timer_tick;
    }
    return 1;
}

int main(int argc, char* argv[])
{
    int next_arg;
    uint16_t n;

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
    n = d_init(patch_data);
    if (n == 0) {
        printf("unable to initialize sound driver\n");
        return -1;
    }
    hiChnl = n >> 8;
    loChnl = n & 0xff;
    atexit(d_terminate);
    VPRINTF(1, "loaded audio driver '%s': %d voice(s), dev_id %d, hiChnl %d loChnl %d\n", sound_driver, drv_info.nr_voices, drv_info.device_id, hiChnl, loChnl);

    vinit();

    timer_hook();
    atexit(timer_unhook);

    for(n = next_arg; n < argc; ++n) {
        play_file_ui(argv[n]);
    }

    return 0;
}
