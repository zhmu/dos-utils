#pragma once

#include <stdint.h>

#define ATTR_BLACK 0x00
#define ATTR_BLUE 0x01
#define ATTR_GREEN 0x02
#define ATTR_CYAN 0x03
#define ATTR_RED 0x04
#define ATTR_MAGENTA 0x05
#define ATTR_BROWN 0x06
#define ATTR_GREY 0x07
#define ATTR_DARK_GREY 0x08
#define ATTR_BRIGHT_BLUE 0x09
#define ATTR_BRIGHT_GREEN 0x0a
#define ATTR_BRIGHT_CYAN 0x0b
#define ATTR_BRIGHT_RED 0x0c
#define ATTR_BRIGHT_MAGENTA 0x0d
#define ATTR_YELLOW 0x0e
#define ATTR_WHITE 0x0f

void vinit();
void vputs(int x, int y, uint8_t attr, const char* s);
void vlog(int ch, const char* fmt, ...);
