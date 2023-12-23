#include <i86.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "video.h"

static uint16_t __far* vmem;

void vinit()
{
    int n;

    // TODO: determine current video mode and adjust vmem accordingly
    vmem = (uint16_t __far*)MK_FP(0xb800, 0);
    for(n = 0; n < 80 * 25; n++) {
        vmem[n] = 0x0720;
    }
}

void vputs(int x, int y, uint8_t attr, const char* s)
{
    uint16_t offs = y * 80 + x;
    while(*s != '\0') {
        vmem[offs] = ((uint16_t)attr << 8) | *s;
        ++s, ++offs;
    }
}

void vlog(int ch, const char* fmt, ...)
{
    char s[60];
    va_list va;
    int n;

    memset(s, ' ', sizeof(s));
    s[sizeof(s) - 1] = '\0';

    va_start(va, fmt);
    n = vsprintf(s, fmt, va); va_end(va);

    s[n] = ' ';
    vputs(12, ch, ATTR_GREY, s);
}
