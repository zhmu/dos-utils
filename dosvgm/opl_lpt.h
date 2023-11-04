#pragma once

#include "types.h"

void opl_lpt2_write_reg(reg8_t reg, val8_t val);
void opl_lpt3_write_reg(reg16_t reg, val8_t val);

void opl_lpt2_reset();
void opl_lpt3_reset();

int opl_lpt_setup(int verbose);
