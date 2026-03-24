#ifndef ZIG_MODULE_EVAL_H
#define ZIG_MODULE_EVAL_H

#include "zig_runtime.h"
#include "value.h"
#include "env.h"
#include "util.h"
#include "sand.h"
#include "deep_copy.h"


#ifndef ZIG_OPTIONAL_Optional_Ptr_z_env_EnvNode
#define ZIG_OPTIONAL_Optional_Ptr_z_env_EnvNode
typedef struct {
    struct z_env_EnvNode* value;
    int has_value;
} Optional_Ptr_z_env_EnvNode;
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


ErrorUnion_Ptr_z_value_Value z_eval_eval(struct z_value_Value*, Optional_Ptr_z_env_EnvNode*, struct z_sand_Sand*, struct z_sand_Sand*);

#endif
