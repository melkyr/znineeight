#ifndef ZIG_MODULE_DECOMPRESS_H
#define ZIG_MODULE_DECOMPRESS_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct Arena;
struct zS_37a939_DictEntry;
struct zS_37a939_Dictionary;

#ifndef ZIG_ERRORUNION_ErrorUnion_void
#define ZIG_ERRORUNION_ErrorUnion_void
struct ErrorUnion_void {
    int err;
    int is_error;
};
typedef struct ErrorUnion_void ErrorUnion_void;
#endif

#include "dict.h"
#include "io.h"


ErrorUnion_void zF_149b62_decompress(void);

#endif
