#ifndef ZIG_MODULE_UTIL_H
#define ZIG_MODULE_UTIL_H

#include "zig_runtime.h"
#include "value.h"


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

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_z_value_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_z_value_Value
typedef struct {
    union {
        struct z_value_Value* payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Ptr_z_value_Value;
#endif


int z_util_mem_eql(Slice_u8, Slice_u8);
ErrorUnion_i64 z_util_parse_int(Slice_u8);
ErrorUnion_Ptr_z_value_Value z_util_deep_copy(struct z_value_Value*, struct z_sand_LispSand*);

#endif
