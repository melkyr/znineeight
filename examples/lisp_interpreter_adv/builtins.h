#ifndef ZIG_MODULE_BUILTINS_H
#define ZIG_MODULE_BUILTINS_H

#include "zig_runtime.h"
#include "value.h"
#include "util.h"
#include "sand.h"


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


ErrorUnion_Ptr_z_value_Value z_builtins_builtin_cons(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_car(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_cdr(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_add(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_sub(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_mul(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_div(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_eq(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_is_nil(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_lt(Slice_Ptr_z_value_Value, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_builtins_builtin_gt(Slice_Ptr_z_value_Value, struct z_sand_Sand*);

#endif
