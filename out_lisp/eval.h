#ifndef ZIG_MODULE_EVAL_H
#define ZIG_MODULE_EVAL_H

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

struct Arena;
struct zS_20f4e1b3_d1871551_Sand;
struct zS_067843b6_fcf51447_Value;
struct zS_9e041cf4_4248a69d_EnvNode;

#ifndef ZIG_OPTIONAL_Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode
#define ZIG_OPTIONAL_Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode
struct Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode {
    struct zS_9e041cf4_4248a69d_EnvNode* value;
    int has_value;
};
typedef struct Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode;
#endif

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
#include "env.h"
#include "util.h"
#include "sand.h"
#include "deep_copy.h"


ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_78e1a1f7_8207c117_eval(struct zS_067843b6_fcf51447_Value*, Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode*, struct zS_20f4e1b3_d1871551_Sand*, struct zS_20f4e1b3_d1871551_Sand*);

#endif
