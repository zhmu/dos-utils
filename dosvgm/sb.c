#include "sb.h"
#include "io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <i86.h>
#include "adlib.h"

uint16_t sb_base = 0x220;
static int sb_opl3;
static int sb_opl_data_delay;

#define SB_PORT_RESET_W 0x6
#define SB_PORT_READ_DATA_R 0xa
#define SB_PORT_COMMAND_DATA_W 0xc
#define SB_PORT_WRITE_BUFFER_STATUS_R 0xc
#define SB_PORT_READ_BUFFER_STATUS_R 0xe

#define SB_PORT_FM1_STATUS_R 0x0
#define SB_PORT_FM1_REG_W 0x0
#define SB_PORT_FM1_DATA_W 0x1
#define SB_PORT_FM2_STATUS_R 0x2
#define SB_PORT_FM2_REG_W 0x2
#define SB_PORT_FM2_DATA_W 0x3

#define SB_PORT_FM_STATUS_R 0x8
#define SB_PORT_FM_REG_W 0x8
#define SB_PORT_FM_DATA_W 0x9

#define DSP_CMD_GET_VERSION 0xe1

static inline void opl_write_reg(int reg_port, int data_port, int status_port, reg8_t reg, val8_t val)
{
    int n;
    outb(reg_port, reg);
    for(n = 0; n < 6; ++n)
        inb(status_port);
    outb(data_port, val);
    for(n = 0; n < sb_opl_data_delay; ++n)
        inb(status_port);
}

static void fm1_write_reg(reg8_t reg, val8_t val)
{
    opl_write_reg(sb_base + SB_PORT_FM1_REG_W, sb_base + SB_PORT_FM1_DATA_W, sb_base + SB_PORT_FM1_STATUS_R, reg, val);
}

static void fm2_write_reg(reg8_t reg, val8_t val)
{
    opl_write_reg(sb_base + SB_PORT_FM2_REG_W, sb_base + SB_PORT_FM2_DATA_W, sb_base + SB_PORT_FM2_STATUS_R, reg, val);
}

void sb_opl2_write_reg(reg8_t reg, val8_t val)
{
    //fm1_write_reg(reg, val);
    adlib_write_reg(reg, val);
}

void sb_opl3_write_reg(reg16_t reg, val8_t val)
{
    if (reg < 0x100) {
        fm1_write_reg(reg & 0xff, val);
    } else {
        fm2_write_reg(reg & 0xff, val);
    }
}

static int sb_dsp_write(uint8_t data)
{
    int n;
    for(n = 0; n < 10; ++n) {
        if ((inb(sb_base + SB_PORT_WRITE_BUFFER_STATUS_R) & 0x80) == 0) {
            outb(sb_base + SB_PORT_COMMAND_DATA_W, data);
            return 1;
        }
        delay(1);
    }
    return 0;
}

static int sb_dsp_read(uint8_t* data)
{
    int n;
    for(n = 0; n < 10; ++n) {
        if (inb(sb_base + SB_PORT_READ_BUFFER_STATUS_R) & 0x80) {
            *data = inb(sb_base + SB_PORT_READ_DATA_R);
            return 1;
        }
        delay(1);
    }
    return 0;
}

static int parse_blaster_env()
{
    unsigned long ul;
    char* ptr = getenv("BLASTER");
    while(ptr != NULL && *ptr != '\0') {
        if (*ptr == 'A' || *ptr == 'a') {
            ul = strtoul(ptr + 1, NULL, 16);
            if (ul) {
                sb_base = ul;
                return 1;
            }
        }

        ptr = strchr(ptr, ' ');
        while(ptr != NULL && *ptr == ' ')
            ++ptr;
    }
    return 0;
}

int sb_detect(int verbose)
{
    uint8_t byte, dsp_ver_hi, dsp_ver_lo;

    if (!parse_blaster_env()) {
        printf("BLASTER environment variable not set or corrupt, defaulting to I/O 0x%x\n", sb_base);
    }

    outb(sb_base + SB_PORT_RESET_W, 1);
    delay(1);
    outb(sb_base + SB_PORT_RESET_W, 0);
    delay(1);
    if (!sb_dsp_read(&byte) || byte != 0xaa) {
        return 0;
    }

    if (!sb_dsp_write(DSP_CMD_GET_VERSION)) {
        printf("dsp not ready for writes\n");
        return 0;
    }
    if (!sb_dsp_read(&dsp_ver_hi) || !sb_dsp_read(&dsp_ver_lo)) {
        printf("dsp not sending data\n");
        return 0;
    }

    if (verbose) {
        printf("SoundBlaster detected, DSP %d.%d\n", dsp_ver_hi, dsp_ver_lo);
    }

    if (dsp_ver_hi > 3) {
        // SB16 and up contain an OPL3
        sb_opl3 = 1;
    } else if (dsp_ver_hi == 3) {
        // SBPRO: four-operator cards return zero (two-operator cards return 6)
        sb_opl3 = inb(0x388) == 0;
    } else {
        // Pre SBPRO cards do not contain an OPL3
        sb_opl3 = 0;
    }

    sb_opl_data_delay = sb_opl3 ? 6 : 35;
    return 1;
}

int sb_has_opl3()
{
    return sb_opl3;
}

void sb_reset()
{
    uint8_t reg;

    /* Reset all registers to zero */
    for(reg = 0; reg < 0xff; ++reg) {
        fm1_write_reg(reg, 0);
        if (sb_opl3) {
            fm2_write_reg(reg, 0);
        }
    }

    /* Reset all sustain levels / release rates */
    for(reg = 0x80; reg < 0x96; ++reg) {
        fm1_write_reg(reg, 0xff);
        if (sb_opl3) {
            fm2_write_reg(reg, 0xff);
        }
    }

    if (sb_opl3) {
        /* Set OPL3 operation */
        fm1_write_reg(5, 1);
    }
}
