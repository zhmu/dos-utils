#pragma once

void sio_setup();
void sio_write(unsigned char ch);
int sio_char_ready();
unsigned char sio_read();
int sio_get_string(char* s, size_t max_len);

