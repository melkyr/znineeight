#ifndef ZIG_MODULE_BUILTINS_H
#define ZIG_MODULE_BUILTINS_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_8_Value_Tag
#define ZIG_ENUM_zE_8_Value_Tag
enum zE_8_Value_Tag {
    zE_8_Value_Tag_Nil = 0,
    zE_8_Value_Tag_Int = 1,
    zE_8_Value_Tag_Bool = 2,
    zE_8_Value_Tag_Symbol = 3,
    zE_8_Value_Tag_Cons = 4,
    zE_8_Value_Tag_Builtin = 5
};
typedef enum zE_8_Value_Tag zE_8_Value_Tag;

#endif /* ZIG_ENUM_zE_8_Value_Tag */

struct zS_4_ConsData;
struct zS_3_Sand;
struct Arena;
struct zS_5_Value;

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_5_Value
struct ErrorUnion_Ptr_zS_5_Value {
    union {
        struct zS_5_Value* payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_5_Value ErrorUnion_Ptr_zS_5_Value;
#endif

#include "value.h"
#include "util.h"
#include "sand.h"


ErrorUnion_Ptr_zS_5_Value zF_42_builtin_cons(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_43_builtin_car(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_44_builtin_cdr(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_45_builtin_add(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_46_builtin_sub(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_47_builtin_mul(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_48_builtin_div(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_49_builtin_eq(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_50_builtin_is_nil(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_51_builtin_lt(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_52_builtin_gt(Slice_Ptr_zS_5_Value, struct zS_3_Sand*);

#endif
