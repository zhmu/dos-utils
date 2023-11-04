#pragma once

#include <stdint.h>
#include <stdio.h>
#include "zlib.h"

void vgmbuffer_set_data_left(uint32_t data_left);
uint16_t vgmbuffer_get_bytes_left();
uint8_t vgmbuffer_pop_byte();
int vgmbuffer_fill(gzFile f);
