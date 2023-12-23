#pragma once

struct DRIVER_INFO {
    uint16_t patch_nr;
    uint8_t nr_voices;
    uint8_t device_id;
};

int driver_info(struct DRIVER_INFO*);
int d_init(void far*);
void d_terminate();
void d_service();

void d_note_on(uint8_t channel, uint8_t note, uint8_t velocity);
void d_note_off(uint8_t channel, uint8_t note, uint8_t velocity);
void d_poly_after(uint8_t channel, uint8_t key, uint8_t pressure);
void d_controller(uint8_t channel, uint8_t control, uint8_t value);
void d_program_change(uint8_t channel, uint8_t patch);
void d_chnl_after(uint8_t channel, uint8_t pressure);
void d_pitch_bend(uint8_t channel, uint8_t lo, uint8_t hi);
void d_set_reverb(uint8_t value);
void d_set_volume(uint8_t value);
void d_sound_on(uint8_t onoff);

