#ifndef ZIG_MODULE_VALUE_H
#define ZIG_MODULE_VALUE_H

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

struct zS_3_Sand;
struct zS_4_ConsData;
struct Arena;
struct zS_5_Value;

#ifndef ZIG_STRUCT_zS_4_ConsData
#define ZIG_STRUCT_zS_4_ConsData
struct zS_4_ConsData {
    struct zS_5_Value* car;
    struct zS_5_Value* cdr;
};

#endif /* ZIG_STRUCT_zS_4_ConsData */

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

#ifndef ZIG_UNION_zS_5_Value
#define ZIG_UNION_zS_5_Value
struct zS_5_Value {
    enum zE_8_Value_Tag tag;
    union {
        i64 Int;
        int Bool;
        Slice_u8 Symbol;
        struct zS_4_ConsData Cons;
        void * Builtin;
    } data;
};

#endif /* ZIG_UNION_zS_5_Value */

#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_5_Value zF_30_alloc_value(struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_33_alloc_cons(struct zS_5_Value*, struct zS_5_Value*, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_34_alloc_int(i64, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_35_alloc_bool(int, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_36_alloc_symbol(Slice_u8, struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_37_alloc_nil(struct zS_3_Sand*);
ErrorUnion_Ptr_zS_5_Value zF_38_alloc_builtin(void *, struct zS_3_Sand*);

#endif
