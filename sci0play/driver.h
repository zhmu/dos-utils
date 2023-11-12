#pragma once

struct DRIVER_INFO {
    uint16_t patch_nr;
    uint16_t nr_voices;
};


int driver_info(struct DRIVER_INFO*);
int d_init();
void d_terminate();
int d_load_sound();
void d_stop_sound();

