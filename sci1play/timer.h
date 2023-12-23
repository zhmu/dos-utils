#pragma once

#include <stdint.h>

void timer_hook();
void timer_unhook();

extern uint32_t timer_tick;
