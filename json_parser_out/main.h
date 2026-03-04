#ifndef ZIG_MODULE_MAIN_H
#define ZIG_MODULE_MAIN_H

#include "zig_runtime.h"
#include "file.h"
#include "json.h"


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

#ifndef ZIG_ERRORUNION_ErrorUnion_Slice_u8
#define ZIG_ERRORUNION_ErrorUnion_Slice_u8
typedef struct {
    union {
        Slice_u8 payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Slice_u8;
#endif

#ifndef ZIG_ERRORUNION_ErrorUnion_z_json_JsonValue
#define ZIG_ERRORUNION_ErrorUnion_z_json_JsonValue
typedef struct {
    union {
        struct z_json_JsonValue payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_z_json_JsonValue;
#endif


int main(int argc, char* argv[]);

#endif
