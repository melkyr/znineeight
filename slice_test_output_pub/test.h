#ifndef ZIG_MODULE_TEST_H
#define ZIG_MODULE_TEST_H

#include "zig_runtime.h"


struct Arena; /* opaque */

#ifndef ZIG_SLICE_Slice_u16
#define ZIG_SLICE_Slice_u16
typedef struct { unsigned short* ptr; usize len; } Slice_u16;
static RETR_UNUSED_FUNC Slice_u16 __make_slice_u16(unsigned short* ptr, usize len) {
    Slice_u16 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif


void public_func(Slice_u16*);

#endif
