#ifndef ZIG_MODULE_EVAL_H
#define ZIG_MODULE_EVAL_H

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

struct Arena;
struct zS_5ed3ca_ConsData;
struct zS_148163_Sand;
struct zS_8e8bb4_EnvNode;
struct zS_5ed3ca_Value;

#ifndef ZIG_OPTIONAL_Optional_Ptr_zS_8e8bb4_EnvNode
#define ZIG_OPTIONAL_Optional_Ptr_zS_8e8bb4_EnvNode
struct Optional_Ptr_zS_8e8bb4_EnvNode {
    struct zS_8e8bb4_EnvNode* value;
    int has_value;
};
typedef struct Optional_Ptr_zS_8e8bb4_EnvNode Optional_Ptr_zS_8e8bb4_EnvNode;
#endif

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
#include "env.h"
#include "util.h"
#include "sand.h"
#include "deep_copy.h"


ErrorUnion_Ptr_zS_5ed3ca_Value zF_d22e0f_eval(struct zS_5ed3ca_Value*, Optional_Ptr_zS_8e8bb4_EnvNode*, struct zS_148163_Sand*, struct zS_148163_Sand*);

#endif
