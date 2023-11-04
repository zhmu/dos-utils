#include "buffer.h"
#include <assert.h>

#define VGMBUFFER_DEBUG 0

#define VGMBUFFER_SIZE 1024
static uint8_t vgmbuffer[VGMBUFFER_SIZE];
static uint16_t vgmbuffer_read_pos = 0;
static uint16_t vgmbuffer_write_pos = 0;
static uint32_t vgmbuffer_data_left;

void vgmbuffer_set_data_left(uint32_t data_left)
{
    vgmbuffer_data_left = data_left;
}

uint16_t vgmbuffer_get_bytes_left()
{
    uint16_t result;
    if (vgmbuffer_read_pos == vgmbuffer_write_pos) {
        result = 0;
    } else if (vgmbuffer_read_pos < vgmbuffer_write_pos) {
        result = vgmbuffer_write_pos - vgmbuffer_read_pos;
    } else {
        result = (VGMBUFFER_SIZE - vgmbuffer_read_pos) + vgmbuffer_write_pos;
    }
    return result;
}

uint8_t vgmbuffer_pop_byte()
{
    uint8_t result;
    if (vgmbuffer_read_pos != vgmbuffer_write_pos) {
        result = vgmbuffer[vgmbuffer_read_pos];
        vgmbuffer_read_pos = (vgmbuffer_read_pos + 1) % VGMBUFFER_SIZE;
    } else {
        result = 0;
        assert(0);
    }
    return result;
}

#define MIN_OF(a, b) ((a) > (b) ? (b) : (a))

int vgmbuffer_fill(gzFile f)
{
    int chunk_len;
    int n;
    if (vgmbuffer_data_left == 0 || vgmbuffer_get_bytes_left() >= VGMBUFFER_SIZE / 2)
        return 1;
#if VGMBUFFER_DEBUG
    printf("\n");
#endif
    if (vgmbuffer_read_pos <= vgmbuffer_write_pos) {
        chunk_len = MIN_OF(VGMBUFFER_SIZE - vgmbuffer_write_pos, vgmbuffer_data_left);
#if VGMBUFFER_DEBUG
        printf("fill 1a, vgmbuffer_write_pos %d size %d\n", vgmbuffer_write_pos, chunk_len);
#endif
        n = gzread(f, &vgmbuffer[vgmbuffer_write_pos], chunk_len);
        vgmbuffer_data_left -= n;
        vgmbuffer_write_pos += n;
        if (vgmbuffer_read_pos > 0) {
            chunk_len = MIN_OF(vgmbuffer_read_pos - 1, vgmbuffer_data_left);
#if VGMBUFFER_DEBUG
            printf("fill 1b, vgmbuffer_write_pos %d size %d\n", 0, chunk_len);
#endif
            n = gzread(f, &vgmbuffer[0], chunk_len);
            vgmbuffer_data_left -= n;
            vgmbuffer_write_pos = n;
        }
#if VGMBUFFER_DEBUG
        printf("fill 1 done %d, left %ld\n", vgmbuffer_get_bytes_left(), vgmbuffer_data_left);
#endif
    } else /* if (vgmbuffer_write_pos < vgmbuffer_read_pos) */ {
        chunk_len = MIN_OF(vgmbuffer_read_pos - vgmbuffer_write_pos - 1, vgmbuffer_data_left);
#if VGMBUFFER_DEBUG
        printf("vgmbuffer_read_pos %d vgmbuffer_write_pos %d\n", vgmbuffer_read_pos, vgmbuffer_write_pos);
        printf("fill 2, vgmbuffer_write_pos %d size %d\n", vgmbuffer_write_pos, chunk_len);
#endif
        n = gzread(f, &vgmbuffer[vgmbuffer_write_pos], chunk_len);
        vgmbuffer_data_left -= n;
        vgmbuffer_write_pos += n;
#if VGMBUFFER_DEBUG
        printf("fill 2 done %d, %d left %ld\n", vgmbuffer_write_pos, vgmbuffer_get_bytes_left(), vgmbuffer_data_left);
#endif
    }
    return 1;
}
