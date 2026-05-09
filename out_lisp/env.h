#ifndef ZIG_MODULE_ENV_H
#define ZIG_MODULE_ENV_H

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
struct zS_9e041cf4_4248a69d_EnvNode;
struct zS_067843b6_fcf51447_Value;

#ifndef ZIG_OPTIONAL_Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode
#define ZIG_OPTIONAL_Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode
struct Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode {
    struct zS_9e041cf4_4248a69d_EnvNode* value;
    int has_value;
};
typedef struct Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode;
#endif

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_9e041cf4_4248a69d_EnvNode
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_9e041cf4_4248a69d_EnvNode
struct ErrorUnion_Ptr_zS_9e041cf4_4248a69d_EnvNode {
    union __ErrorData_Ptr_zS_9e041cf4_4248a69d_EnvNode_LispError {
        int err;
        struct zS_9e041cf4_4248a69d_EnvNode* payload;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_9e041cf4_4248a69d_EnvNode ErrorUnion_Ptr_zS_9e041cf4_4248a69d_EnvNode;
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

#ifndef ZIG_STRUCT_zS_9e041cf4_4248a69d_EnvNode
#define ZIG_STRUCT_zS_9e041cf4_4248a69d_EnvNode
struct zS_9e041cf4_4248a69d_EnvNode {
    Slice_u8 symbol;
    struct zS_067843b6_fcf51447_Value* value;
    Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode next;
};

#endif /* ZIG_STRUCT_zS_9e041cf4_4248a69d_EnvNode */

#include "value.h"
#include "sand.h"
#include "util.h"


Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode zF_9e041cf4_fdd3a5d3_env_find_node(Slice_u8, Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode);
ErrorUnion_Ptr_zS_067843b6_fcf51447_Value zF_9e041cf4_69ea9227_env_lookup(Slice_u8, Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode);
ErrorUnion_Ptr_zS_9e041cf4_4248a69d_EnvNode zF_9e041cf4_d598831d_env_extend(Slice_u8, struct zS_067843b6_fcf51447_Value*, Optional_Ptr_zS_9e041cf4_4248a69d_EnvNode, struct zS_20f4e1b3_d1871551_Sand*);

#endif
