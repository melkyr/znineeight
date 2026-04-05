#ifndef ZIG_MODULE_ENV_H
#define ZIG_MODULE_ENV_H

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

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_8e8bb4_EnvNode
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_8e8bb4_EnvNode
struct ErrorUnion_Ptr_zS_8e8bb4_EnvNode {
    union {
        struct zS_8e8bb4_EnvNode* payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_8e8bb4_EnvNode ErrorUnion_Ptr_zS_8e8bb4_EnvNode;
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

#ifndef ZIG_STRUCT_zS_8e8bb4_EnvNode
#define ZIG_STRUCT_zS_8e8bb4_EnvNode
struct zS_8e8bb4_EnvNode {
    Slice_u8 symbol;
    struct zS_5ed3ca_Value* value;
    Optional_Ptr_zS_8e8bb4_EnvNode next;
};

#endif /* ZIG_STRUCT_zS_8e8bb4_EnvNode */

#include "value.h"
#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_5ed3ca_Value zF_8e8bb4_env_lookup(Slice_u8, Optional_Ptr_zS_8e8bb4_EnvNode);
ErrorUnion_Ptr_zS_8e8bb4_EnvNode zF_8e8bb4_env_extend(Slice_u8, struct zS_5ed3ca_Value*, Optional_Ptr_zS_8e8bb4_EnvNode, struct zS_148163_Sand*);

#endif
