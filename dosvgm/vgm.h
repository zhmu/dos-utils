#pragma once

#include <stdint.h>

#define VGM_ID 0x206d6756

#pragma pack(push, 1)
struct VGM_HEADER {
    /* 0x00 */ uint32_t id;
    /* 0x04 */ uint32_t eof_offset;
    /* 0x08 */ uint32_t version_number;
    /* 0x0c */ uint32_t sn76489_clock;
    /* 0x10 */ uint32_t ym2413_clock;
    /* 0x14 */ uint32_t gd3_offset;
    /* 0x18 */ uint32_t total_samples;
    /* 0x1c */ uint32_t loop_offset;
    /* 0x20 */ uint32_t loop_samples;
    /**1.0**/
    /* 0x24 */ uint32_t rate;
    /**1.10**/
    /* 0x28 */ uint16_t sn76489_feedback;
    /* 0x2a */ uint8_t  sn76489_sr_width;
    /**1.51**/
    /* 0x2b */ uint8_t  sn76489_flags;
    /**1.10**/
    /* 0x2c */ uint32_t ym2612_clock;
    /* 0x30 */ uint32_t ym2151_clock;
    /**1.50**/
    /* 0x34 */ uint32_t vgm_data_offset;
    /**1.51**/
    /* 0x38 */ uint32_t sega_pcm_clock;
    /* 0x3c */ uint32_t sega_pcm_interface_reg;
    /* 0x40 */ uint32_t rf5c68_clock;
    /* 0x44 */ uint32_t ym2203_clock;
    /* 0x48 */ uint32_t ym2608_clock;
    /* 0x4c */ uint32_t ym2610_ym2610b_clock;
    /* 0x50 */ uint32_t ym3812_clock;
    /* 0x54 */ uint32_t ym3526_clock;
    /* 0x58 */ uint32_t y8950_clock;
    /* 0x5c */ uint32_t ymf262_clock;
    /* 0x60 */ uint32_t ymf278b_clock;
    /* 0x64 */ uint32_t ymf271_clock;
    /* 0x68 */ uint32_t ymz280b_clock;
    /* 0x6c */ uint32_t rf5c164_clock;
    /* 0x70 */ uint32_t pwm_clock;
    /* 0x74 */ uint32_t ay8910_clock;
    /* 0x78 */ uint8_t  ay8910_chip_type;
    /* 0x79 */ uint8_t  ay8910_flags;
    /* 0x7a */ uint8_t  ym2203_ay8910_flags;
    /* 0x7b */ uint8_t  ym2608_ay8910_flags;
    /**1.60**/
    /* 0x7c */ uint8_t  volume_modifier;
    /* 0x7d */ uint8_t  reserved_7d;
    /* 0x7e */ uint8_t  loop_base;
    /**1.51**/
    /* 0x7f */ uint8_t  loop_modifier;
    /**1.61**/
    /* 0x80 */ uint32_t gameboy_dmg_clock;
    /* 0x84 */ uint32_t nes_apu_clock;
    /* 0x88 */ uint32_t multipcm_clock;
    /* 0x8c */ uint32_t upd7759_clock;
    /* 0x90 */ uint32_t okim6258_clock;
    /* 0x94 */ uint8_t  okim6258_flags;
    /* 0x95 */ uint8_t  k054539_flags;
    /* 0x96 */ uint8_t  c140_chip_type;
    /* 0x97 */ uint8_t  reserved_97;
    /* 0x98 */ uint32_t okim6295_clock;
    /* 0x9c */ uint32_t k051649_k052539_clock;
    /* 0xa0 */ uint32_t k054539_clock;
    /* 0xa4 */ uint32_t huc6280_clock;
    /* 0xa8 */ uint32_t c140_clock;
    /* 0xac */ uint32_t k053260_clock;
    /* 0xb0 */ uint32_t pokey_clock;
    /* 0xb4 */ uint32_t qsound_clock;
    /**1.71**/
    /* 0xb8 */ uint32_t scsp_clock;
    /**1.70**/
    /* 0xbc */ uint32_t extra_header_offset;
    /**1.71**/
    /* 0xc0 */ uint32_t wonderswan_clock;
    /* 0xc4 */ uint32_t vsu_clock;
    /* 0xc8 */ uint32_t saa1099_clock;
    /* 0xcc */ uint32_t es5503_clock;
    /* 0xd0 */ uint32_t es5505_es5506_clock;
    /* 0xd4 */ uint8_t  es5503_nr_output_channels;
    /* 0xd5 */ uint8_t  es5505_es5506_nr_output_channels;
    /* 0xd6 */ uint8_t  c352_clock_divider;
    /* 0xd8 */ uint32_t x1_010_clock;
    /* 0xdc */ uint32_t c352_clock;
    /* 0xe0 */ uint32_t ga20_clock;
};
#pragma pack(pop)

