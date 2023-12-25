#include "sound.h"
#include <stdio.h>
#include <string.h>
#include "driver.h"
#include "midi.h"
#include "util.h"
#include "video.h"

#define CH_LOG(ti, ...) \
    vlog((ti)->channel, __VA_ARGS__)

struct TRACK_INFO track_info[MAX_TRACKS];
static uint8_t far* sound_data;

static uint8_t getb(struct TRACK_INFO* ti)
{
    uint8_t v = sound_data[ti->offset];
    ++ti->offset;
    return v;
}

// [NoteOff]
static void note_off(struct TRACK_INFO* ti)
{
    uint8_t ch, cl;
    ch = getb(ti); // note
    cl = getb(ti); // velocity
    CH_LOG(ti, "NoteOff %d %d %d", ch, cl);
    ti->cur_note = 0xff;
    d_note_off(ti->channel, ch, cl);
}

// [NoteOn]
static void note_on(struct TRACK_INFO* ti)
{
    uint8_t ch, cl;
    ch = getb(ti); // note
    cl = getb(ti); // velocity
    CH_LOG(ti, "NoteOn %d %d", ch, cl);
    ti->cur_note = ch;
    d_note_on(ti->channel, ch, cl);
}

// [PolyAfterTch]
static void poly_after(struct TRACK_INFO* ti)
{
    uint8_t ch, cl;
    ch = getb(ti); // note
    cl = getb(ti); // pressure
    CH_LOG(ti, "PolyAferTch %d %d", ch, cl);
    d_poly_after(ti->channel, ch, cl);
}

// [Controller]
static void controller(struct TRACK_INFO* ti)
{
    uint8_t ch, cl;
    ch = getb(ti); // controller
    cl = getb(ti); // value
    CH_LOG(ti, "Controller %d %d", ch, cl);
    // TODO: VOLCTRL needs scaling [clrVolRequest]
    // maybe more?
    d_controller(ti->channel, ch, cl);
}

// [ProgramChange]
static void pchange(struct TRACK_INFO* ti)
{
    uint8_t cl;
    cl = getb(ti); // program
    CH_LOG(ti, "PChange %d", cl);
    d_program_change(ti->channel, cl);
}

// [ChnlAfterTch]
static void chnl_after(struct TRACK_INFO* ti)
{
    uint8_t cl;
    cl = getb(ti); // pressure
    CH_LOG(ti, "ChnlAfter %d", cl);
    d_chnl_after(ti->channel, cl);
}

// [PitchBend]
static void pbend(struct TRACK_INFO* ti)
{
    uint8_t ch, cl;
    ch = getb(ti); // msb
    cl = getb(ti); // lsb
    CH_LOG(ti, "PBend %d %d", ch, cl);
    // TODO this needs more work
    d_pitch_bend(ti->channel, ch, cl);
}

// [SysEx]
static void sysex(struct TRACK_INFO* ti)
{
    uint8_t v;
    CH_LOG(ti, "sysex", ti->channel);
    while(1) {
        v = getb(ti);
        if (v == MIDI_EOX)
            break;
    }
}

static void ControlChnl(struct TRACK_INFO* ti)
{
    uint8_t v, w;
    int n;

    switch(ti->command) {
        case PCHANGE:
            // [doCue]
            v = getb(ti);
            if (v == 127) {
                // Loop set - get rest value (do not consume byte, this is
                // used in the loop below)
                v = sound_data[ti->offset];
                if (v == TIMINGOVER) {
                    ti->rest = 0x8000 | 240;
                } else {
                    ti->rest = v;
                }
                ti->command = 0xc0;
                for(n = 0; n < MAX_TRACKS; ++n) {
                    track_info[n].loop_point = track_info[n].offset;
                    track_info[n].loop_rest = track_info[n].rest;
                    track_info[n].loop_command = track_info[n].command;
                }
                // Note that we'll continue looking at the next byte (v), which
                // seems to be the intention... it'll be a rest byte
                ti->rest = 0;
                CH_LOG(ti, "[control] loop set");
                break;
            }  else {
                // [notLoopCue]
                CH_LOG(ti, "[control]: set signal %d", v);
            }
            break;
        case CONTROLLER:
            // [doContrlr]
            v = getb(ti);
            w = getb(ti);
            CH_LOG(ti, "[control] controller %d %d", v, w);
            break;
        default:
            CH_LOG(ti, "[control] unrecognized command %x", ti->command);
            break;
    }
}

void sound_server()
{
    int ch = 0;
    uint8_t v;

    for (ch = 0; ch < MAX_TRACKS; ++ch) {
        struct TRACK_INFO* ti = &track_info[ch];
        if (ti->offset == 0) continue; // frozen

        // notFrozenTrk
        if (ti->rest > 0) {
            --ti->rest;
            if (ti->rest == 0x8000) {
                v = getb(ti);
                if (v == TIMINGOVER) {
                    ti->rest = 0x8000 | 240;
                } else {
                    ti->rest = 0;
                }
            }
            continue;
        }

        // [restOver]
        while(1) {
            // [parseCommand]

            // Peek at next byte
            v = sound_data[ti->offset];
            if (v >= 0x80) {
                // It's a command, update
                if (v == END_OF_TRACK) {
                    ti->offset = 0;
                    goto out_track;
                }

                // [parseIt]
                ti->command = v & 0xf0; // ah
                ti->channel = v & 0x0f; // al
                ++ti->offset;
            }

            // [notEndTrk]
            if (ti->channel == 15) {
                ControlChnl(ti);
                if (ti->offset == 0) {
                    // done with track - don't parse more commands
                    goto out_track;
                }
            } else {
                // [notControlCh]
                switch(ti->command) {
                    case NOTEOFF:
                        note_off(ti);
                        break;
                    case NOTEON:
                        note_on(ti);
                        break;
                    case POLYAFTER:
                        poly_after(ti);
                        break;
                    case CONTROLLER:
                        controller(ti);
                        break;
                    case PCHANGE:
                        pchange(ti);
                        break;
                    case CHNLAFTER:
                        chnl_after(ti);
                        break;
                    case PBEND:
                        pbend(ti);
                        break;
                    case SYSEX:
                        sysex(ti);
                        break;
                    default:
                        printf("[%d] unknown command %x\n", ch, ti->command);
                        ti->offset = 0; // shut down track
                        break;
                }
            }

            // [nextComm] Update delay
            v = getb(ti);
            if (v == 0) {
                // No delay, keep handling commands
                continue;
            }
            if (v == TIMINGOVER) {
                ti->rest = 0x8000 | (240 - 1);
            } else {
                ti->rest = v - 1;
            }
            break;
        }
out_track:
        (void)0;
    }
}

int sound_load(const char* path)
{
    sound_data = load_file(path);
    return sound_data != NULL;
}

int sound_init(uint8_t drv_dev_id)
{
    uint8_t far* sound_ptr = sound_data;
    uint8_t dev_id, v;
    struct TRACK_INFO tmp_ti[MAX_TRACKS];
    int tmp_idx;
    int n;
    int found = 0;
    struct TRACK_INFO* ti;

    sound_ptr = sound_data;
    if (sound_ptr[0] == 0xf0) {
        // sound priority = sound_ptr[1];
        sound_ptr += 8;
    }

    while(1) {
        dev_id = sound_ptr[0];
        ++sound_ptr;
        if (dev_id == 0xff) {
            break;
        }

        tmp_idx = 0;
        memset(tmp_ti, 0, sizeof(tmp_ti));
        while(sound_ptr[0] != 0xff) {
            tmp_ti[tmp_idx].offset = *(uint16_t*)&sound_ptr[2];
            tmp_ti[tmp_idx].length = *(uint16_t*)&sound_ptr[4];
            sound_ptr += 6;
            ++tmp_idx;
        }
        ++sound_ptr;

        if (dev_id == drv_dev_id) {
            memcpy(track_info, tmp_ti, sizeof(track_info));
            ++found;
            break;
        }
    }
    if (!found) return 0;

    // initialize tracks
    for(n = 0; n < MAX_TRACKS; ++n) {
        uint16_t offset = track_info[n].offset;
        ti = &track_info[n];

        if (ti->offset == 0) break;
        // TODO More stuff here that needs processing
        ti->command = END_OF_TRACK; // TODO
        ti->channel = sound_data[offset];
        ti->command = CONTROLLER | ti->channel;
        v = sound_data[offset + 12];
        if(v == TIMINGOVER) {
            ti->rest = 0x8000 | 240;
        } else {
            ti->rest = v;
        }
        ti->offset = offset + 13;
        v = track_info[n].channel;
        ti->channel &= 0xf;
        if (v & 0x10) {
            // Ghost track
            ti->rest = 0;
            ti->flags |= FLAG_GHOST;
            // ti->offset = 3;
        }
        if (v & 0x20) {
            // Locked
            ti->flags |= FLAG_LOCKED;
        }
        if (v & 0x40) {
            // Muted
            ti->mute = 1;
        }

        // Reset state
        ti->cur_note = 0xff;

        // Loop info
        ti->loop_point = offset + 3;
        ti->loop_rest = 3;
        ti->loop_command = 0;

        // Mixing 'copy SOUND data' / [UpdateChannel2] to immediately set the values
        d_controller(ti->channel, CTRL_ALLNOFF, 0);

        v = sound_data[offset + 8]; // reverbMode
        d_set_reverb(v);
        v = sound_data[offset + 1]; // cPriVoice
        d_controller(ti->channel, CTRL_NUMNOTES, v & 0xf);
        v = sound_data[offset + 4]; // cProgram
        d_program_change(ti->channel, v);
        v = sound_data[offset + 8]; // volume
        v = sound_data[offset + 11]; // cPan
        d_controller(ti->channel, CTRL_PANCTRL, v);
        d_controller(ti->channel, CTRL_CURNOTE, ti->cur_note);

        // cDamprBend reset ??

        // TODO: reset sDataInc, sTimer, sSignal, sFadeDest, sFadeTicks, sFadeCount, sFadeSteps, sPause
    }
    return 1;
}

void sound_loop()
{
    int n;
    for(n = 0; n < MAX_TRACKS; ++n) {
        track_info[n].offset = track_info[n].loop_point;
        track_info[n].rest = track_info[n].loop_rest;
        track_info[n].command = track_info[n].loop_command;
    }
}

