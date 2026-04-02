#ifndef ZIG_MODULE_EVAL_H
#define ZIG_MODULE_EVAL_H

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

struct Arena;
struct zS_4_ConsData;
struct zS_3_Sand;
struct zS_6_EnvNode;
struct zS_5_Value;

#ifndef ZIG_OPTIONAL_Optional_Ptr_zS_6_EnvNode
#define ZIG_OPTIONAL_Optional_Ptr_zS_6_EnvNode
struct Optional_Ptr_zS_6_EnvNode {
    struct zS_6_EnvNode* value;
    int has_value;
};
typedef struct Optional_Ptr_zS_6_EnvNode Optional_Ptr_zS_6_EnvNode;
#endif

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
#include "env.h"
#include "util.h"
#include "sand.h"
#include "deep_copy.h"


ErrorUnion_Ptr_zS_5_Value zF_75_eval(struct zS_5_Value*, Optional_Ptr_zS_6_EnvNode*, struct zS_3_Sand*, struct zS_3_Sand*);

#endif
