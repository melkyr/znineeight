#ifndef ZIG_MODULE_UTIL_H
#define ZIG_MODULE_UTIL_H

#include "zig_runtime.h"


#ifndef ZIG_ERRORUNION_ErrorUnion_i64
#define ZIG_ERRORUNION_ErrorUnion_i64
typedef struct {
    union {
        i64 payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_i64;
#endif

extern int z_util_LispError;

int z_util_mem_eql(Slice_u8, Slice_u8);
ErrorUnion_i64 z_util_parse_int(Slice_u8);

#endif
