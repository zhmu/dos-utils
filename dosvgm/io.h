#pragma once

void outb(int, int);
#pragma aux outb = \
    "out dx, al", \
    parm [dx] [ax]

int inb(int);
#pragma aux inb = \
    "in al, dx", \
    parm [dx] \
    modify exact [ax]

void int3();
#pragma aux int3  = \
    "int 3", \
    modify exact []

