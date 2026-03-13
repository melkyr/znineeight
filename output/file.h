#ifndef ZIG_MODULE_FILE_H
#define ZIG_MODULE_FILE_H

#include "zig_runtime.h"


#ifndef ZIG_OPTIONAL_Optional_Ptr_void
#define ZIG_OPTIONAL_Optional_Ptr_void
typedef struct {
    void * value;
    int has_value;
} Optional_Ptr_void;
#endif

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

#ifndef ZIG_OPTIONAL_Optional_Ptr_Ptr_u8
#define ZIG_OPTIONAL_Optional_Ptr_Ptr_u8
typedef struct {
    unsigned char const** value;
    int has_value;
} Optional_Ptr_Ptr_u8;
#endif

extern void * z_file_File;
extern int z_file_FileError;

ErrorUnion_Slice_u8 z_file_readFile(void *, Slice_u8);

#endif
