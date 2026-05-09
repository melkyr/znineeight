#ifndef ZIG_MODULE_SAND_H
#define ZIG_MODULE_SAND_H

#include "zig_runtime.h"
#include "zig_special_types.h"

struct zS_20f4e1b3_d1871551_Sand;
struct Arena;

#ifndef ZIG_STRUCT_zS_20f4e1b3_d1871551_Sand
#define ZIG_STRUCT_zS_20f4e1b3_d1871551_Sand
struct zS_20f4e1b3_d1871551_Sand {
    unsigned char* start;
    usize pos;
    usize end;
};

#endif /* ZIG_STRUCT_zS_20f4e1b3_d1871551_Sand */

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_u8
#define ZIG_ERRORUNION_ErrorUnion_Ptr_u8
struct ErrorUnion_Ptr_u8 {
    union __ErrorData_Ptr_u8_LispError {
        int err;
        unsigned char* payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_u8 ErrorUnion_Ptr_u8;
#endif

#include "util.h"


struct zS_20f4e1b3_d1871551_Sand zF_20f4e1b3_46f8f755_sand_init(Slice_u8);
ErrorUnion_Ptr_u8 zF_20f4e1b3_171f30d0_sand_alloc(struct zS_20f4e1b3_d1871551_Sand*, usize, usize);
void zF_20f4e1b3_b1ebd39a_sand_reset(struct zS_20f4e1b3_d1871551_Sand*);

#endif
