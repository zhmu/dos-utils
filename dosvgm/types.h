#pragma once

#include <stdint.h>

typedef uint32_t vgmtick_t;

/* Register/value types */
typedef uint8_t reg8_t;
typedef uint16_t reg16_t;
typedef uint8_t val8_t;

/* VGM player types */
typedef void (*audio_reset_t)(void);
typedef void (*ym3526_write_reg_t)(reg8_t, val8_t);
typedef void (*ymf262_write_reg_t)(reg16_t, val8_t);
