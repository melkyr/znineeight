#ifndef ZIG_MODULE_VALUE_H
#define ZIG_MODULE_VALUE_H

#include "zig_runtime.h"
#include "sand.h"
#include "util.h"


enum z_value_Value_Tag {
    z_value_Value_Tag_Nil = 0,
    z_value_Value_Tag_Int = 1,
    z_value_Value_Tag_Bool = 2,
    z_value_Value_Tag_Symbol = 3,
    z_value_Value_Tag_Cons = 4,
    z_value_Value_Tag_Builtin = 5
};
typedef enum z_value_Value_Tag z_value_Value_Tag;

struct z_value_Value;
struct z_value_Value {
    enum z_value_Value_Tag tag;
    union {
        i64 Int;
        int Bool;
        Slice_u8 Symbol;
        struct {
            struct z_value_Value* car;
            struct z_value_Value* cdr;
        } Cons;
        void * Builtin;
    } data;
};

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


ErrorUnion_Ptr_z_value_Value z_value_alloc_value(struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_cons(struct z_value_Value*, struct z_value_Value*, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_int(i64, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_bool(int, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_symbol(Slice_u8, struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_nil(struct z_sand_Sand*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_builtin(void *, struct z_sand_Sand*);

#endif
