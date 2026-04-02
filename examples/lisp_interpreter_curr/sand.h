#ifndef ZIG_MODULE_SAND_H
#define ZIG_MODULE_SAND_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct zS_3_Sand;
struct Arena;

#ifndef ZIG_STRUCT_zS_3_Sand
#define ZIG_STRUCT_zS_3_Sand
struct zS_3_Sand {
    unsigned char* start;
    usize pos;
    usize end;
};

#endif /* ZIG_STRUCT_zS_3_Sand */

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_u8
#define ZIG_ERRORUNION_ErrorUnion_Ptr_u8
struct ErrorUnion_Ptr_u8 {
    union {
        unsigned char* payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_u8 ErrorUnion_Ptr_u8;
#endif

#include "util.h"


struct zS_3_Sand zF_24_sand_init(Slice_u8);
ErrorUnion_Ptr_u8 zF_25_sand_alloc(struct zS_3_Sand*, usize, usize);
void zF_26_sand_reset(struct zS_3_Sand*);

#endif
