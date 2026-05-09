#ifndef ZIG_SPECIAL_TYPES_H
#define ZIG_SPECIAL_TYPES_H

#include <stddef.h>
#include "zig_compat.h"

#ifndef ZIG_TUPLE_EMPTY
#define ZIG_TUPLE_EMPTY
struct Tuple_empty { char __dummy; };
typedef struct Tuple_empty Tuple_empty;
#endif

#ifndef ZIG_SLICE_Slice_u8
#define ZIG_SLICE_Slice_u8
struct Slice_u8 { unsigned char* ptr; usize len; };
typedef struct Slice_u8 Slice_u8;
ZIG_INLINE ZIG_UNUSED Slice_u8 __make_slice_u8(const char* ptr, usize len) {
    Slice_u8 s;
    s.ptr = (unsigned char*)ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_Ptr_zS_067843b6_fcf51447_Value
#define ZIG_SLICE_Slice_Ptr_zS_067843b6_fcf51447_Value
struct Slice_Ptr_zS_067843b6_fcf51447_Value { struct zS_067843b6_fcf51447_Value** ptr; usize len; };
typedef struct Slice_Ptr_zS_067843b6_fcf51447_Value Slice_Ptr_zS_067843b6_fcf51447_Value;
ZIG_INLINE ZIG_UNUSED Slice_Ptr_zS_067843b6_fcf51447_Value __make_slice_Ptr_zS_067843b6_fcf51447_Value(struct zS_067843b6_fcf51447_Value** ptr, usize len) {
    Slice_Ptr_zS_067843b6_fcf51447_Value s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#endif /* ZIG_SPECIAL_TYPES_H */
