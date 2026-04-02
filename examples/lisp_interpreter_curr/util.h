#ifndef ZIG_MODULE_UTIL_H
#define ZIG_MODULE_UTIL_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct Arena;

#ifndef ZIG_ERRORUNION_ErrorUnion_i64
#define ZIG_ERRORUNION_ErrorUnion_i64
struct ErrorUnion_i64 {
    union {
        i64 payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_i64 ErrorUnion_i64;
#endif


extern int zV_95_LispError;

int zF_11_mem_eql(Slice_u8, Slice_u8);
ErrorUnion_i64 zF_12_parse_int(Slice_u8);

#endif
