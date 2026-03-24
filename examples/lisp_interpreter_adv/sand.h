#ifndef ZIG_MODULE_SAND_H
#define ZIG_MODULE_SAND_H

#include "zig_runtime.h"
#include "util.h"


struct z_sand_Sand {
    unsigned char* start;
    usize pos;
    usize end;
};

struct z_sand_Sand;
#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_u8
#define ZIG_ERRORUNION_ErrorUnion_Ptr_u8
typedef struct {
    union {
        unsigned char* payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Ptr_u8;
#endif


struct z_sand_Sand z_sand_sand_init(Slice_u8);
ErrorUnion_Ptr_u8 z_sand_sand_alloc(struct z_sand_Sand*, usize, usize);
void z_sand_sand_reset(struct z_sand_Sand*);

#endif
