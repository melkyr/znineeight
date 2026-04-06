#ifndef ZIG_MODULE_VALUE_H
#define ZIG_MODULE_VALUE_H

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

struct zS_148163_Sand;
struct Arena;
struct zS_5ed3ca_Value;

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

#ifndef ZIG_UNION_zS_5ed3ca_Value
#define ZIG_UNION_zS_5ed3ca_Value
#ifndef ZIG_STRUCT_zS_1a36c1_anon_1
#define ZIG_STRUCT_zS_1a36c1_anon_1
struct zS_1a36c1_anon_1 {
    struct zS_5ed3ca_Value* car;
    struct zS_5ed3ca_Value* cdr;
};

#endif /* ZIG_STRUCT_zS_1a36c1_anon_1 */

struct zS_5ed3ca_Value {
    enum zE_1a36c1_Value_Tag tag;
    union {
        i64 Int;
        int Bool;
        Slice_u8 Symbol;
        struct zS_1a36c1_anon_1 Cons;
        void * Builtin;
    } data;
};

#endif /* ZIG_UNION_zS_5ed3ca_Value */

struct zS_1a36c1_anon_1;
#include "sand.h"
#include "util.h"


ErrorUnion_Ptr_zS_5ed3ca_Value zF_5ed3ca_alloc_value(struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_5ed3ca_alloc_cons(struct zS_5ed3ca_Value*, struct zS_5ed3ca_Value*, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_5ed3ca_alloc_int(i64, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_5ed3ca_alloc_bool(int, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_5ed3ca_alloc_symbol(Slice_u8, struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_5ed3ca_alloc_nil(struct zS_148163_Sand*);
ErrorUnion_Ptr_zS_5ed3ca_Value zF_5ed3ca_alloc_builtin(void *, struct zS_148163_Sand*);

#endif
