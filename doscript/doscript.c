#include <stdio.h>
#include <conio.h>
#include <stdint.h>
#include <dos.h>
#include <io.h>
#include <unistd.h>
#include <process.h>
#include <time.h>
#include <stdlib.h>
#include <malloc.h>
#include <i86.h>

#define MAX_ARGS 10
#define MAX_ARG_LENGTH 32

#define MAX_CHUNK_SIZE 8192

char exec_arg[MAX_ARGS][MAX_ARG_LENGTH];
char far* receive_buffer;

void serial_init_irqs();
void serial_cleanup_irqs();

#if 0
// COM1
int com_port = 0x3f8;
int com_irq = 4;
#else
// COM2
int com_port = 0x2f8;
int com_irq = 3;
#endif

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

static int serial_chars_avail()
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
#if 0
    if (result != 0)
        printf("serial_chars_avail %d\n", result);
#endif
    return result;
}

int serial_pop_char()
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
    //printf("serial_pop_char %d\n", result);
    return result;
}

static void serial_setup()
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
    //outb(0x21, inb(0x21) & 0xef);
}

static int sio_char_ready()
{
    return serial_chars_avail() > 0;
}

static unsigned char sio_read()
{
    unsigned char ch;
    while (serial_chars_avail() == 0)
        ;

    return serial_pop_char() & 0xff;
}

static void sio_write(unsigned char ch)
{
    while((inb(com_port + SIO_LSR) & 0x20) == 0);
    outb(com_port, ch);
}

static int sio_get_string(char* s, size_t max_len)
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

static uint32_t sio_receive_16()
{
    uint16_t v = 0;
    v |= (uint32_t)sio_read() << 8;
    v |= (uint32_t)sio_read();
    return v;
}

static uint32_t sio_receive_32()
{
    uint32_t v = 0;
    v |= (uint32_t)sio_read() << 24;
    v |= (uint32_t)sio_read() << 16;
    v |= (uint32_t)sio_read() << 8;
    v |= (uint32_t)sio_read();
    return v;
}

static void sio_write_16(uint16_t v)
{
    sio_write(v >> 8);
    sio_write(v & 0xff);
}

static uint16_t crc16(uint16_t crc, uint8_t byte)
{
    int n;
    crc = crc ^ (byte << 8);
    for(n = 0; n < 8; ++n) {
        const auto carry = crc & 0x8000;
        crc = crc << 1;
        if (carry) {
            crc = crc ^ 0x1021;
        }
    }
    return crc;
}

static int receive_file(FILE* f)
{
    uint32_t file_len = sio_receive_32();
    uint32_t received = 0;
    uint16_t a, b, c, n;
    uint32_t p;
    clock_t timeout;

    while(received < file_len) {
        const char cmd = sio_read();
        switch(cmd) {
            case '-': // abort
                printf("< Receive aborted\n");
                return -1;
            case 'c': // chunk
                a = sio_receive_16(); // chunk length
                if (a > MAX_CHUNK_SIZE) {
                    sio_write('-');
                    printf("< Aborting, chunk size too large (got %u, can provide %u)\n", a, MAX_CHUNK_SIZE);
                    return -1;
                }
                b = sio_receive_16(); // chunk checksum
                for(n = 0; n < a; ++n) {
                    uint8_t ch = sio_read();
                    receive_buffer[n] = ch;
                }
                c = 0;
                for(n = 0; n < a; ++n) {
                    uint8_t ch = receive_buffer[n];
                    c = crc16(c, ch);
                    fwrite(&ch, 1, 1, f);
                }
                if (b == c) {
                    sio_write('+');
                    received += a;
                } else {
                    printf("! Checksum mismatch (got %u, expected %u)\n", c, b);
                    sio_write('-');
                }
                break;
            case 's': // seek
                p = sio_receive_32();
                if (fseek(f, p, SEEK_SET) == 0) {
                    sio_write('+');
                } else {
                    sio_write('-');
                }
                break;
            default:
                printf("receive_file: unexpected '%c', aborting\n", cmd);
                return 1;
        }
    }

    sio_write('^');
    printf("< Receive completed\n");
    return 0;
}

static int execute(const char* prog)
{
    const char* argv[MAX_ARGS + 1];
    unsigned char num_args;
    int n;

    num_args = sio_read();
    //printf("num_args %d\n", num_args);
    if (num_args >= MAX_ARGS) {
        sio_write('-');
        return -1;
    }
    sio_write('+');

    for(n = 0; n < num_args; ++n) {
        int r = sio_get_string(exec_arg[n], MAX_ARG_LENGTH);
        if (r < 0) return -1;
        argv[n] = exec_arg[n];
        //printf("args %d: '%s'\n", n,exec_arg[n]);
    }
    argv[n] = NULL;

    printf("> Executing '%s' with arguments", prog);
    for(n = 0; n < num_args; ++n) {
        printf(" '%s'", argv[n]);
    }
    printf("\n");
    n = spawnv(P_WAIT, prog, argv);
    sio_write('^');
    sio_write_16(n);

    printf("< Execute finished (%d)\n", n);
    return 0;
}

static int handshake()
{
    unsigned char cmd;
    while(1) {
        if (kbhit()) {
            printf("< aborted!\n");
            return 0;
        }
        if (sio_char_ready()) {
            cmd = sio_read();
            if (cmd == '!') {
                printf("< OK\n");
                break;
            }
            if (cmd == '#') {
                continue;
            }
        }
        sio_write('?');
        delay(1000);
    }
    return 1;
}

int main()
{
    char s[64];
    int n;
    FILE* f = NULL;
    unsigned char cmd;

    printf("DOScript version 0.1 - (c) 2023 Rink Springer, rink@rink.nu\n\n");
    receive_buffer = _fmalloc(MAX_CHUNK_SIZE);
    if (receive_buffer == NULL) {
        printf("Out of memory!\n");
        return 1;
    }
    serial_setup();

    printf("> Waiting for handshake...\n");
    if (!handshake()) return 1;

    while(1) {
        int running = 1;
        printf("> Waiting for command...\n");
        while(running && !sio_char_ready()) {
            if (kbhit()) running = 0;
        }
        if (!running) break;
        cmd = sio_read();
        switch(cmd) {
            case '#': // handshake
                printf("> Handshaking...\n");
                if (!handshake()) return 1;
                break;
            case 'W': // write to file
                n = sio_get_string(s, sizeof(s));
                if (n <= 0) {
                    sio_write('-');
                    continue;
                }
                if (access(s, F_OK) == 0) {
                    sio_write('E'); // E = already exists
                    continue;
                }
                f = fopen(s, "wb");
                if (f == NULL) {
                    sio_write('I'); // I = I/O error
                    continue;
                }
                printf("> Receiving '%s'...\n", s);
                sio_write('+');
                receive_file(f);
                fclose(f);
                break;
            case 'E': // execute
                n = sio_get_string(s, sizeof(s));
                printf("e, %d, '%s'\n", n, s);
                if (n <= 0) {
                    sio_write('-');
                    continue;
                }
                if (access(s, X_OK) != 0) {
                    sio_write('N'); // N = not executable
                    continue;
                }
                printf("e, step 2\n");
                sio_write('+');
                execute(s);
                break;
            case 'R': // remove
                n = sio_get_string(s, sizeof(s));
                if (n <= 0) {
                    sio_write('-');
                    continue;
                }
                if (access(s, F_OK) != 0) {
                    sio_write('N'); // N = does not exist
                    continue;
                }
                if (remove(s) == 0) {
                    sio_write('+');
                } else {
                    sio_write('-');
                }
                break;
            default:
                printf("? Unrecognized command '%c', aborting\n", cmd);
                return 0;
        }
    }
    return 0;
}
