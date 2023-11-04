#pragma once

#include "types.h"

void adlib_write_reg(reg8_t reg, val8_t val);
val8_t adlib_read_status();
int adlib_detect();
void adlib_reset();
