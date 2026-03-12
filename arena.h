#ifndef ZIG_MODULE_ARENA_H
#define ZIG_MODULE_ARENA_H

#include "zig_runtime.h"


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


Slice_u8 z_arena_alloc_bytes(usize);

#endif
