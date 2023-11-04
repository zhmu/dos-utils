#pragma once

#include "types.h"

void sb_opl2_write_reg(reg8_t reg, val8_t val);
void sb_opl3_write_reg(reg16_t reg, val8_t val);
int sb_has_opl3();
int sb_detect(int verbose);
void sb_reset();
