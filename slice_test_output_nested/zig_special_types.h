#ifndef ZIG_SPECIAL_TYPES_H
#define ZIG_SPECIAL_TYPES_H

#include <stddef.h>

#ifndef ZIG_SLICE_Slice_f32
#define ZIG_SLICE_Slice_f32
typedef struct { float* ptr; usize len; } Slice_f32;
static RETR_UNUSED_FUNC Slice_f32 __make_slice_f32(float* ptr, usize len) {
    Slice_f32 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_i32
#define ZIG_SLICE_Slice_i32
typedef struct { int* ptr; usize len; } Slice_i32;
static RETR_UNUSED_FUNC Slice_i32 __make_slice_i32(int* ptr, usize len) {
    Slice_i32 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#endif /* ZIG_SPECIAL_TYPES_H */
