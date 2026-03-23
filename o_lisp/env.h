#ifndef ZIG_MODULE_ENV_H
#define ZIG_MODULE_ENV_H

#include "zig_runtime.h"
#include "value.h"
#include "util.h"
#include "sand.h"


struct z_env_EnvNode;
#ifndef ZIG_OPTIONAL_Optional_Ptr_z_env_EnvNode
#define ZIG_OPTIONAL_Optional_Ptr_z_env_EnvNode
typedef struct {
    struct z_env_EnvNode* value;
    int has_value;
} Optional_Ptr_z_env_EnvNode;
#endif

struct z_env_EnvNode {
    Slice_u8 symbol;
    struct z_value_Value* value;
    Optional_Ptr_z_env_EnvNode next;
};

#ifndef ZIG_ERRORUNION_ErrorUnion_Ptr_z_env_EnvNode
#define ZIG_ERRORUNION_ErrorUnion_Ptr_z_env_EnvNode
typedef struct {
    union {
        struct z_env_EnvNode* payload;
        int err;
    } data;
    int is_error;
} ErrorUnion_Ptr_z_env_EnvNode;
#endif

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


ErrorUnion_Ptr_z_value_Value z_env_env_lookup(Slice_u8, Optional_Ptr_z_env_EnvNode);
ErrorUnion_Ptr_z_env_EnvNode z_env_env_extend(Slice_u8, struct z_value_Value*, Optional_Ptr_z_env_EnvNode, struct z_sand_LispSand*);

#endif
