#ifndef ZIG_MODULE_ARENA_H
#define ZIG_MODULE_ARENA_H

#include "zig_runtime.h"


struct z_arena_LispArena;
#ifndef ZIG_SLICE_Slice_u8
#define ZIG_SLICE_Slice_u8
typedef struct { unsigned char* ptr; usize len; } Slice_u8;
static RETR_UNUSED_FUNC Slice_u8 __make_slice_u8(unsigned char* ptr, usize len) {
    Slice_u8 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

struct z_arena_LispArena {
    unsigned char* start;
    unsigned char* pos;
    unsigned char* end;
};

struct z_arena_Arena; /* opaque */

struct z_arena_Arena;
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


struct z_arena_LispArena z_arena_lisp_arena_init(Slice_u8);
ErrorUnion_Ptr_u8 z_arena_lisp_alloc(struct z_arena_LispArena*, usize, usize);
void z_arena_lisp_reset(struct z_arena_LispArena*);

#endif
