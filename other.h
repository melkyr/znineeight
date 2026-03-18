#ifndef ZIG_MODULE_OTHER_H
#define ZIG_MODULE_OTHER_H

#include "zig_runtime.h"


struct z_other_Arena; /* opaque */

struct z_other_Arena;
#ifndef ZIG_OPTIONAL_Optional_Ptr_i32
#define ZIG_OPTIONAL_Optional_Ptr_i32
typedef struct {
    int* value;
    int has_value;
} Optional_Ptr_i32;
#endif


Optional_Ptr_i32 z_other_get_ptr(void);

#endif
