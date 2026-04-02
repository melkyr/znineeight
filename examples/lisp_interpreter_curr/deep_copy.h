#ifndef ZIG_MODULE_DEEP_COPY_H
#define ZIG_MODULE_DEEP_COPY_H

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
#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_5_Value zF_56_deep_copy(struct zS_5_Value*, struct zS_3_Sand*);

#endif
