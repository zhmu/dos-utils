#include "util.h"
#include <malloc.h>
#include <stdio.h>

char far* load_file(const char* fname)
{
    char far* buf = NULL;
    size_t size;

    FILE* f = fopen(fname, "rb");
    if (f == NULL) goto err;

    fseek(f, 0, SEEK_END);
    size = ftell(f);
    rewind(f);

    // Use halloc() as it guarantees the offset is 0; this is mainly important
    // for the audio driver which expects this
    buf = halloc(size, 1);
    if (buf == NULL) goto err;

    if (!fread(buf, size, 1, f)) goto err;
    fclose(f);
    return buf;

err:
    if (buf != NULL) free(buf);
    fclose(f);
    return NULL;
}

