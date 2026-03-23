#ifndef ZIG_MODULE_SAND_H
#define ZIG_MODULE_SAND_H

#include "zig_runtime.h"


struct z_sand_LispSand;
struct z_sand_LispSand {
    unsigned char* start;
    unsigned char* pos;
    unsigned char* end;
};

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


struct z_sand_LispSand z_sand_lisp_sand_init(Slice_u8);
ErrorUnion_Ptr_u8 z_sand_lisp_sand_alloc(struct z_sand_LispSand*, usize, usize);
void z_sand_lisp_sand_reset(struct z_sand_LispSand*);

#endif
