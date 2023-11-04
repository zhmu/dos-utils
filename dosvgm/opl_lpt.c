#include "opl_lpt.h"
#include <i86.h>
#include <stdio.h>
#include "io.h"

uint16_t lpt_base = 0x378; // LPT1

#define LPT_STATUS_BUSY (1<<7)
#define LPT_STATUS_nACK (1<<6)
#define LPT_STATUS_OUT_OF_PAPER (1<<5)
#define LPT_STATUS_SELECTED (1<<4)
#define LPT_STATUS_NO_ERROR (1<<3)
#define LPT_STATUS_NO_IRQ (1<<2)

#define LPT_CONTROL_NOT_SELECT (1 << 3)
#define LPT_CONTROL_INIT (1 << 2)
#define LPT_CONTROL_AUTO_LINEFEED (1 << 1)
#define LPT_CONTROL_NOT_STROBE (1 << 0)

#define LPT_PORT_DATA_W 0
#define LPT_PORT_STATUS_R 1
#define LPT_PORT_CONTROL_W 2

static void opl_lpt_delay(unsigned int cycles)
{
    unsigned int n;
    for(n = 0; n < cycles; ++n)
        inb(lpt_base + LPT_PORT_CONTROL_W);
}

static void opl_lpt_write_data(val8_t val)
{
    outb(lpt_base + LPT_PORT_DATA_W, val);
    outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_SELECT | LPT_CONTROL_INIT);
    outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_SELECT);
    outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_SELECT | LPT_CONTROL_INIT);
}

void opl_lpt2_write_reg(reg8_t reg, val8_t val)
{
    outb(lpt_base + LPT_PORT_DATA_W, reg);
    outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_NOT_SELECT | LPT_CONTROL_INIT);
    outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_NOT_SELECT);
    outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_NOT_SELECT | LPT_CONTROL_INIT);
    opl_lpt_delay(6);

    opl_lpt_write_data(val);
    opl_lpt_delay(35);
}

void opl_lpt2_reset()
{
    int n;
    for(n = 0; n < 256; ++n) {
        opl_lpt2_write_reg(n, 0);
    }
}

void opl_lpt3_write_reg(reg16_t reg, val8_t val)
{
    outb(lpt_base + LPT_PORT_DATA_W, reg & 0xff);
    if (reg < 0x100) {
        outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_NOT_SELECT | LPT_CONTROL_INIT);
        outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_NOT_SELECT);
        outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_NOT_SELECT | LPT_CONTROL_INIT);
    } else {
        outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_INIT);
        outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE);
        outb(lpt_base + LPT_PORT_CONTROL_W, LPT_CONTROL_NOT_STROBE | LPT_CONTROL_INIT);
    }
    opl_lpt_delay(6);
    opl_lpt_write_data(val);
    opl_lpt_delay(6);
}

void opl_lpt3_reset()
{
    int n;
    for(n = 0; n < 512; ++n) {
        opl_lpt3_write_reg(n, 0);
    }
}

int opl_lpt_setup(int verbose)
{
    int n;
    uint16_t* lptaddr = MK_FP(0x40, 0x8);
    for(n = 0; n < 3; ++n, ++lptaddr) {
        if (*lptaddr == 0) continue;
        if (verbose) {
            printf("OPL-LPT: Using I/O address 0x%x\n", *lptaddr);
        }
        lpt_base = *lptaddr;
        return 1;
    }
    printf("OPL-LPT: No parallel ports detected, cannot continue\n");
    return 0;
}
