#ifndef ZIG_MODULE_PAL_H
#define ZIG_MODULE_PAL_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct zS_26b5a9a4_43f95de6_Sand;
struct Arena;

#ifndef ZIG_OPTIONAL_Optional_Ptr_void
#define ZIG_OPTIONAL_Optional_Ptr_void
struct Optional_Ptr_void {
    void * value;
    int has_value;
};
typedef struct Optional_Ptr_void Optional_Ptr_void;
#endif

#ifndef ZIG_OPTIONAL_Optional_Slice_u8
#define ZIG_OPTIONAL_Optional_Slice_u8
struct Optional_Slice_u8 {
    Slice_u8 value;
    int has_value;
};
typedef struct Optional_Slice_u8 Optional_Slice_u8;
#endif

#include "allocator.h"


Optional_Slice_u8 zF_6873a254_5576b025_readFile(Slice_u8, struct zS_26b5a9a4_43f95de6_Sand*);
void zF_6873a254_7fd3683c_stdout_write(Slice_u8);
void zF_6873a254_1dc3fa43_stderr_write(Slice_u8);
void zF_6873a254_25b9f2e7_exit(unsigned char);
void zF_6873a254_00b68800_initArgs(int, unsigned char const**);
int zF_6873a254_edf9c674_argCount(void);
unsigned char const* zF_6873a254_b1633bd7_argGet(int);

#endif
