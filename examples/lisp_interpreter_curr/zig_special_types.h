#ifndef ZIG_SPECIAL_TYPES_H
#define ZIG_SPECIAL_TYPES_H

#include <stddef.h>

#ifndef ZIG_SLICE_Slice_u8
#define ZIG_SLICE_Slice_u8
struct Slice_u8 { unsigned char* ptr; usize len; };
typedef struct Slice_u8 Slice_u8;
static RETR_UNUSED_FUNC Slice_u8 __make_slice_u8(const char* ptr, usize len) {
    Slice_u8 s;
    s.ptr = (unsigned char*)ptr;
    s.len = len;
    return s;
}
#endif

#ifndef ZIG_SLICE_Slice_Ptr_zS_5ed3ca_Value
#define ZIG_SLICE_Slice_Ptr_zS_5ed3ca_Value
struct Slice_Ptr_zS_5ed3ca_Value { struct zS_5ed3ca_Value** ptr; usize len; };
typedef struct Slice_Ptr_zS_5ed3ca_Value Slice_Ptr_zS_5ed3ca_Value;
static RETR_UNUSED_FUNC Slice_Ptr_zS_5ed3ca_Value __make_slice_Ptr_zS_5ed3ca_Value(struct zS_5ed3ca_Value** ptr, usize len) {
    Slice_Ptr_zS_5ed3ca_Value s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

#endif /* ZIG_SPECIAL_TYPES_H */
