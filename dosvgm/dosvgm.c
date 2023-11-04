#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <conio.h>
#include <string.h>
#include <i86.h>
#include "adlib.h"
#include "buffer.h"
#include "types.h"
#include "io.h"
#include "vgm.h"
#include "zlib.h"
#include "opl_lpt.h"
#include "sb.h"

void timer_hook();
void timer_unhook();

#define ADD_EXTRA_TICK_PER_NR_OF_TICKS 18

int verbose = 0;
volatile vgmtick_t player_tick = 0;
const uint8_t extra_tick_per = ADD_EXTRA_TICK_PER_NR_OF_TICKS;
uint8_t ticks_pending_for_extra = ADD_EXTRA_TICK_PER_NR_OF_TICKS;
vgmtick_t next_tick = 0;

vgmtick_t vgm_total_ticks;

audio_reset_t reset_audio_fn = NULL;
ym3526_write_reg_t ym3526_write_reg = NULL;
ymf262_write_reg_t ymf262_write_reg = NULL;

int load_vgm(gzFile f)
{
    struct VGM_HEADER hdr;
    uint32_t data_offset;
    uint32_t data_length;

    memset(&hdr, 0, sizeof(hdr));
    if (!gzread(f, &hdr, sizeof(hdr))) {
        fprintf(stderr, "cannot read header\n");
        return 0;
    }

    if (hdr.id != VGM_ID) {
        fprintf(stderr, "not a vgm file\n");
        return 0;
    }

    if (hdr.version_number >= 0x150) {
        data_offset = hdr.vgm_data_offset + 0x34;
    } else {
        data_offset = 0x40;
    }

    if (data_offset < sizeof(hdr)) {
        memset((char*)&hdr + data_offset, 0, sizeof(struct VGM_HEADER) - data_offset);
    }

    data_length = hdr.eof_offset - data_offset - 4;
    vgm_total_ticks = hdr.total_samples;
    if (verbose) {
        printf("VGM data: %lu bytes at offset 0x%lx\n", data_length, data_offset);
        printf("YM3812 clock: %lu Hz\n", hdr.ym3812_clock);
        printf("YMF262 clock: %lu Hz\n", hdr.ymf262_clock);
    }
    if (hdr.ym3812_clock != 0 && ym3526_write_reg == NULL) {
        fprintf(stderr, "vgm requires YM3526, which is unavailable\n");
        return 0;
    }
    if (hdr.ymf262_clock != 0 && ymf262_write_reg == NULL) {
        fprintf(stderr, "vgm requires YMF262, which is unavailable\n");
        return 0;
    }
    if (hdr.ym3812_clock == 0 && hdr.ymf262_clock == 0) {
        fprintf(stderr, "vgm requires neither YM3526 nor YMF262, cannot play\n");
        return 0;
    }

    vgmbuffer_set_data_left(data_length);
    gzseek(f, data_offset, SEEK_SET);
    if (!vgmbuffer_fill(f)) {
        printf("unable to fill buffer, exiting\n");
        return 0;
    }
    return 1;
}

static void reprogram_pit()
{
    /*
     * VGM sample rate is 44100 Hz
     * PIT rate is 1193182 Hz
     * mapping them gives 1193182 / 44100 = 27.056..., so one
     * VGM tick is rougly 27 PIT ticks
     *
     * Every ~18 (ADD_EXTRA_TICK_PER_NR_OF_TICKS) ticks, we'll have missed a
     * full tick, so every 18 ticks, we add an extra tick to compensate. This
     * is stored in 'extra_tick_per', which the timer_irq uses.
     */
    const uint16_t reload_value = 27;
    _disable();
    outb(0x43, 0x34); /* pit channel 0: mode 2 (rate generator), set lo/hi counter */
    outb(0x40, reload_value & 0xff);
    outb(0x40, reload_value >> 8);
    _enable();
}

static int update_player(gzFile f)
{
    uint8_t aa, dd;
    uint8_t cmd;

    //printf("+update_player player_tick %lu next_tick %lu\n", player_tick, next_tick);
    while(next_tick <= player_tick) {
        if (!vgmbuffer_fill(f)) {
            printf("Unable to fill buffer, exiting\n");
            return 0;
        }

        cmd = vgmbuffer_pop_byte();
        //printf("command %02x (left %d)\n", cmd, vgmbuffer_get_bytes_left());
        switch(cmd) {
            case 0x5a: // YM3812, write value dd to register aa
                aa = vgmbuffer_pop_byte();
                dd = vgmbuffer_pop_byte();
                ym3526_write_reg(aa, dd);
                break;
            case 0x5e: // YMF262 port 0, write value dd to register aa
                // XXX guesswork
                aa = vgmbuffer_pop_byte();
                dd = vgmbuffer_pop_byte();
                ymf262_write_reg(aa, dd);
                break;
            case 0x5f: // YMF262 port 1, write value dd to register aa
                aa = vgmbuffer_pop_byte();
                dd = vgmbuffer_pop_byte();
                ymf262_write_reg(0x100 | (reg16_t)aa, dd);
                break;
            case 0x61: // Wait n samples
                aa = vgmbuffer_pop_byte();
                dd = vgmbuffer_pop_byte();
                next_tick += aa;
                next_tick += (uint16_t)dd << 8;
                break;
            case 0x62: // Wait 1/60th of a second */
                next_tick += 735;
                break;
            case 0x63: // Wait 1/50th of a second
                next_tick += 882;
                break;
            case 0x66:
                printf("\nEnd of song\n");
                return 0;
            case 0x70: case 0x71: case 0x72: case 0x73:
            case 0x74: case 0x75: case 0x76: case 0x77:
            case 0x78: case 0x79: case 0x7a: case 0x7b:
            case 0x7c: case 0x7d: case 0x7e: case 0x7f:
                // Wait n+1 samples, 0<=n<=15
                next_tick += 1 + (cmd & 0xf);
                break;
            default:
                printf("unrecognized command %x !\n", cmd);
                return 0;
        }
    }
    //printf("-update_player player_tick %lu next_tick %lu\n", player_tick, next_tick);
    return 1;
}

static char* vgmtick_format(char* out, vgmtick_t ticks)
{
    int sec, ms, min;
    sec = ticks / 44100;
    ms = (ticks % 44100) / 44;
    if (sec >= 60) {
        min = sec / 60;
        sec = sec % 60;
        sprintf(out, "%02d:%02d.%03d", min, sec, ms);
    } else {
        sprintf(out, "%02d.%03d", sec, ms);
    }
    return out;
}

static void help(const char* prog)
{
    printf("DOSVGM version 1.0 - (c) 2023 Rink Springer <rink@rink.nu>\n");
    printf("\n");
    printf("usage: %s [options] file.vgm\n\n", prog);
    printf("options can be:\n");
    printf("  -h, -help   this help\n");
    printf("  -v          verbose\n");
    printf("\n");
    printf("hardware devices:\n");
    printf("  -a          adlib output\n");
    printf("  -sb         SoundBlaster output\n");
    printf("  -opl2lpt    OPL2LPT output\n");
    printf("  -opl3lpt    OPL3LPT output\n");
    printf("\n");
}

static int parse_args(int argc, char* argv[])
{
    int adlib = 0;
    int sb = 0;
    int opl2lpt = 0;
    int opl3lpt = 0;

    int n;
    for(n = 1; n < argc; ++n) {
        if (argv[n][0] != '-') continue;

        if (strcmp(argv[n]+1, "h") == 0 || strcmp(argv[n]+1, "help") == 0) {
            help(argv[0]);
            return 0;
        }

        if (strcmp(argv[n]+1, "a") == 0) {
            ++adlib;
            continue;
       }
        if (strcmp(argv[n]+1, "sb") == 0) {
            ++sb;
            continue;
       }
        if (strcmp(argv[n]+1, "v") == 0) {
            ++verbose;
            continue;
        }
        if (strcmp(argv[n]+1, "opl2lpt") == 0) {
            ++opl2lpt;
            continue;
        }
        if (strcmp(argv[n]+1, "opl3lpt") == 0) {
            ++opl3lpt;
            continue;
        }

        printf("unrecognized commandline argument - use -h / -help for help\n");
        return 1;
    }

    if ((adlib + sb + opl2lpt + opl3lpt) > 1) {
        printf("multiple sound hardware devices specified - use -h/ -help for help\n");
        return 0;
    }

    if ((adlib + sb + opl2lpt + opl3lpt) == 0) {
        printf("no sound card specified, defaulting to SoundBlaster...\n");
        ++sb;
    }

    if (adlib) {
        if (!adlib_detect()) {
            printf("adlib not detected\n");
            return 0;
        }
        reset_audio_fn = adlib_reset;
        ym3526_write_reg = adlib_write_reg;
    } else if (sb) {
        if (!sb_detect(verbose)) {
            printf("SoundBlaster not detected\n");
            return 0;
        }
        reset_audio_fn = sb_reset;
        ym3526_write_reg = sb_opl2_write_reg;
        if (sb_has_opl3()) {
            if (verbose) {
                printf("SoundBlaster contains OPL3\n");
            }
            ymf262_write_reg = sb_opl3_write_reg;
        }
    } else if (opl2lpt) {
        if (!opl_lpt_setup(verbose)) return 0;
        reset_audio_fn = opl_lpt2_reset;
        ym3526_write_reg = opl_lpt2_write_reg;
    } else if (opl3lpt) {
        if (!opl_lpt_setup(verbose)) return 0;
        reset_audio_fn = opl_lpt3_reset;
        ymf262_write_reg = opl_lpt3_write_reg;
    }
    return 1;
}

int main(int argc, char* argv[])
{
    char song_length[32];
    char play_position[32];
    int quit = 0;
    gzFile f;

    if (argc < 2) {
        help(argv[0]);
        return 1;
    }

    if (!parse_args(argc, argv)) {
        return 1;
    }

    if (reset_audio_fn == NULL) {
        printf("no sound hardware specified - use -h / -help for help\n");
        return 1;
    }
    reset_audio_fn();

    f = gzopen(argv[argc - 1], "rb");
    if (f == NULL) {
        fprintf(stderr, "cannot open '%s'\n", argv[argc - 1]);
        return 0;
    }

    if (!load_vgm(f)) {
        gzclose(f);
        return 1;
    }
    vgmtick_format(song_length, vgm_total_ticks);

    reprogram_pit();
    timer_hook();
    atexit(timer_unhook);

    while(!quit && !kbhit()) {
        vgmtick_format(play_position, player_tick);
        if (verbose) {
            printf("Playing %s / %s (tick %lu next_tick %lu bufleft %d)    \r",
                play_position,
                song_length,
                player_tick, next_tick,
                vgmbuffer_get_bytes_left());
        } else {
            printf("Playing %s / %s     \r",
                play_position, song_length);
        }

        if (!update_player(f)) {
            ++quit;
        }
    }

    reset_audio_fn();
    gzclose(f);
    return 0;
}
