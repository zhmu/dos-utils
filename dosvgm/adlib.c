#include "adlib.h"
#include <i86.h>
#include "io.h"

#define ADLIB_INDEX_W 0x388
#define ADLIB_STATUS_R 0x388
#define ADLIB_DATA_W 0x389

void adlib_write_reg(reg8_t reg, val8_t val)
{
    int n;
    outb(ADLIB_INDEX_W, reg);
    for(n = 0; n < 6; ++n)
        inb(ADLIB_STATUS_R);
    outb(ADLIB_DATA_W, val);
    for(n = 0; n < 35; ++n)
        inb(ADLIB_STATUS_R);
}

val8_t adlib_read_status()
{
    return inb(ADLIB_STATUS_R);
}

int adlib_detect()
{
    uint8_t a, b;
    adlib_write_reg(4, 0x60); // reset both timers
    adlib_write_reg(4, 0x80); // enable interrupts
    a = adlib_read_status();
    adlib_write_reg(2, 0xff); // timer 2
    adlib_write_reg(4, 0x21); // start timer 1
    delay(1); // 1 ms, >80microseconds
    b = adlib_read_status();
    adlib_write_reg(4, 0x60); // reset both timers
    adlib_write_reg(4, 0x80); // enable interrupts
    return (a & 0xe0) == 0 && (b & 0xe0) == 0xc0;
}

void adlib_reset()
{
    uint8_t reg;
    for(reg = 1; reg <= 0xf5; ++reg)
        adlib_write_reg(reg, 0);
}
