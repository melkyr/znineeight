#ifndef ZIG_MODULE_DEEP_COPY_H
#define ZIG_MODULE_DEEP_COPY_H

#include "zig_runtime.h"
#include "value.h"
#include "sand.h"
#include "util.h"


#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_z_value_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_z_value_Value
typedef struct {
    union {
        struct z_value_Value* payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Ptr_z_value_Value;
#endif


ErrorUnion_Ptr_z_value_Value z_deep_copy_deep_copy(struct z_value_Value*, struct z_sand_Sand*);

#endif
