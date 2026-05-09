#ifndef ZIG_MODULE_UTIL_H
#define ZIG_MODULE_UTIL_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct Arena;

#ifndef ZIG_ERRORUNION_ErrorUnion_i64
#define ZIG_ERRORUNION_ErrorUnion_i64
struct ErrorUnion_i64 {
    union __ErrorData_i64_LispError {
        int err;
        i64 payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_i64 ErrorUnion_i64;
#endif



int zF_3b847fd5_6e83bbbe_mem_eql(Slice_u8, Slice_u8);
ErrorUnion_i64 zF_3b847fd5_d9a1fc1b_parse_int(Slice_u8);
int zF_3b847fd5_c22c5c9f_points_to_arena(void *, unsigned char*, usize);

#endif
