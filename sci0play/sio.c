#include <stdlib.h>
#include <i86.h>
#include "io.h"

#if 0
// COM1
int com_port = 0x3f8;
int com_irq = 4;
#else
// COM2
int com_port = 0x2f8;
int com_irq = 3;
#endif

// serial.asm
void serial_init_irqs();
void serial_cleanup_irqs();

#define BUFFER_SIZE 64

unsigned char com_buffer[BUFFER_SIZE];
unsigned char com_buf_read_ptr = 0;
unsigned char com_buf_write_ptr = 0;

#define SIO_DLAB_LO     0                       // dlab (if enabled), lo
#define SIO_DLAB_HI     1                       // dlab (if enabled), hi
#define SIO_IER         1                       // interrupt enable register
#define SIO_FIFO        2                       // interrupt identification/fifo
#define SIO_LCR         3                       // line control register
#define SIO_MCR         4                       // modem control register
#define SIO_LSR         5                       // line status register

static int sio_chars_avail()
{
    int result;
    _disable();
    if (com_buf_read_ptr == com_buf_write_ptr) {
        result = 0;
    } else if (com_buf_read_ptr < com_buf_write_ptr) {
        result = com_buf_write_ptr - com_buf_read_ptr;
    } else {
        result = (BUFFER_SIZE - com_buf_read_ptr) + com_buf_write_ptr;
    }
    _enable();
    return result;
}

static int sio_pop_char()
{
    int result;

    _disable();
    if (com_buf_read_ptr != com_buf_write_ptr) {
        result = com_buffer[com_buf_read_ptr];
        com_buf_read_ptr = (com_buf_read_ptr + 1) % BUFFER_SIZE;
    } else {
        result = 0;
    }
    _enable();
    return result;
}

void sio_setup()
{
    serial_init_irqs();
    atexit(serial_cleanup_irqs);

    outb(com_port + SIO_IER, 0);       // reset interrupts
    outb(com_port + SIO_LCR, 0x80);    // access DLAB by setting bit 7 of LCR
    outb(com_port + SIO_DLAB_HI, 0);
    outb(com_port + SIO_DLAB_LO, 1);   // 115200 baud
    //outb(com_port + SIO_DLAB_LO, 12);   // 9600 baud
    outb(com_port + SIO_LCR, 3);       // 8N1
    outb(com_port + SIO_FIFO, 0xc7);   // enable/clear FIFOs
    outb(com_port + SIO_MCR, 0xb);     // enable 'output#2'
    outb(com_port + SIO_IER, 1);       // enable interrupts (receive)

    outb(0x21, inb(0x21) & ~(1 << com_irq)); // enable serial port IRQ
}

int sio_char_ready()
{
    return sio_chars_avail() > 0;
}

unsigned char sio_read()
{
    while (sio_chars_avail() == 0)
        ;

    return sio_pop_char() & 0xff;
}

void sio_write(unsigned char ch)
{
    while((inb(com_port + SIO_LSR) & 0x20) == 0);
    outb(com_port, ch);
}

int sio_get_string(char* s, size_t max_len)
{
    size_t n = 0;
    while (n < max_len - 1) {
        const char ch = sio_read();
        if (ch == '$') break;
        s[n] = ch;
        ++n;
    }
    s[n] = '\0';
    return n;
}
