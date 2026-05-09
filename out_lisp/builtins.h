#ifndef ZIG_MODULE_BUILTINS_H
#define ZIG_MODULE_BUILTINS_H

#include "zig_runtime.h"
#include "zig_special_types.h"

#ifndef ZIG_ENUM_zE_067843b6_ad7213d2_Value_Tag
#define ZIG_ENUM_zE_067843b6_ad7213d2_Value_Tag
enum zE_067843b6_ad7213d2_Value_Tag {
    zE_067843b6_ad7213d2_Value_Tag_Nil = 0,
    zE_067843b6_ad7213d2_Value_Tag_Int = 1,
    zE_067843b6_ad7213d2_Value_Tag_Bool = 2,
    zE_067843b6_ad7213d2_Value_Tag_Symbol = 3,
    zE_067843b6_ad7213d2_Value_Tag_Cons = 4,
    zE_067843b6_ad7213d2_Value_Tag_Builtin = 5
};
typedef enum zE_067843b6_ad7213d2_Value_Tag zE_067843b6_ad7213d2_Value_Tag;

#endif /* ZIG_ENUM_zE_067843b6_ad7213d2_Value_Tag */

struct zS_20f4e1b3_d1871551_Sand;
struct Arena;
struct zS_067843b6_fcf51447_Value;

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_067843b6_fcf51447_Value
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_067843b6_fcf51447_Value
struct ErrorUnion_Ptr_zS_067843b6_fcf51447_Value {
    union __ErrorData_Ptr_zS_067843b6_fcf51447_Value_LispError {
        int err;
        struct zS_067843b6_fcf51447_Value* payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_067843b6_fcf51447_Value ErrorUnion_Ptr_zS_067843b6_fcf51447_Value;
#endif

#include "value.h"
#include "util.h"
#include "sand.h"


ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_7b8fbdad_builtin_cons(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_68b33fd6_builtin_car(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_82c034b7_builtin_cdr(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_942f4f2b_builtin_add(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_a367698a_builtin_sub(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_d968fe86_builtin_mul(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_dbb3dce3_builtin_div(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_51e92822_builtin_eq(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_d06fc224_builtin_is_nil(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_58d36cd8_builtin_lt(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_4620f6ed_5aef467b_builtin_gt(Slice_Ptr_zS_067843b6_fcf51447_Value, struct zS_20f4e1b3_d1871551_Sand*);

#endif
