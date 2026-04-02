#ifndef ZIG_MODULE_ENV_H
#define ZIG_MODULE_ENV_H

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

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_zS_6_EnvNode
#define ZIG_ERRORUNION_ErrorUnion_Ptr_zS_6_EnvNode
struct ErrorUnion_Ptr_zS_6_EnvNode {
    union {
        struct zS_6_EnvNode* payload;
        int err;
    } data;
    int is_error;
};
typedef struct ErrorUnion_Ptr_zS_6_EnvNode ErrorUnion_Ptr_zS_6_EnvNode;
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

#ifndef ZIG_STRUCT_zS_6_EnvNode
#define ZIG_STRUCT_zS_6_EnvNode
struct zS_6_EnvNode {
    Slice_u8 symbol;
    struct zS_5_Value* value;
    Optional_Ptr_zS_6_EnvNode next;
};

#endif /* ZIG_STRUCT_zS_6_EnvNode */

#include "value.h"
#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_5_Value zF_60_env_lookup(Slice_u8, Optional_Ptr_zS_6_EnvNode);
ErrorUnion_Ptr_zS_6_EnvNode zF_61_env_extend(Slice_u8, struct zS_5_Value*, Optional_Ptr_zS_6_EnvNode, struct zS_3_Sand*);

#endif
