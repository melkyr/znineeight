#ifndef ZIG_MODULE_BUILTINS_H
#define ZIG_MODULE_BUILTINS_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_1a36c1_Value_Tag
#define ZIG_ENUM_zE_1a36c1_Value_Tag
enum zE_1a36c1_Value_Tag {
    zE_1a36c1_Value_Tag_Nil = 0,
    zE_1a36c1_Value_Tag_Int = 1,
    zE_1a36c1_Value_Tag_Bool = 2,
    zE_1a36c1_Value_Tag_Symbol = 3,
    zE_1a36c1_Value_Tag_Cons = 4,
    zE_1a36c1_Value_Tag_Builtin = 5
};
typedef enum zE_1a36c1_Value_Tag zE_1a36c1_Value_Tag;

#endif /* ZIG_ENUM_zE_1a36c1_Value_Tag */

struct zS_148163_Sand;
struct Arena;
struct zS_5ed3ca_Value;

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5ed3ca_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5ed3ca_Value
struct ErrorUnion_Ptr_zS_5ed3ca_Value {
    union {
        struct zS_5ed3ca_Value* payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_5ed3ca_Value ErrorUnion_Ptr_zS_5ed3ca_Value;
#endif

#include "value.h"
#include "util.h"
#include "sand.h"


ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_cons(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_car(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_cdr(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_add(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_sub(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_mul(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_div(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_eq(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_is_nil(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_lt(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_c1e489_builtin_gt(Slice_Ptr_zS_5ed3ca_Value, struct zS_148163_Sand*);

#endif
