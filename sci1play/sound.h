#pragma once

#include <stdint.h>

#define MAX_TRACKS 16

#define FLAG_LOCKED 1
#define FLAG_GHOST 2

struct TRACK_INFO {
    // values read from sound.nnn
    uint16_t offset;
    uint16_t length;
    // state
    uint16_t rest;
    uint8_t command;
    uint8_t channel;
    uint8_t flags;
    uint8_t mute;
    // loop
    uint16_t loop_point;
    uint16_t loop_rest;
    uint8_t loop_command;
    // info
    uint16_t cur_note;
};

extern struct TRACK_INFO track_info[MAX_TRACKS];

int sound_load(const char* path);
int sound_init(uint8_t dev_id);
void sound_server();
void sound_loop();
