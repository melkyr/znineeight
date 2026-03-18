#ifndef ZIG_MODULE_VALUE_H
#define ZIG_MODULE_VALUE_H

#include "zig_runtime.h"
#include "arena.h"


enum z_value_ValueTag {
    z_value_ValueTag_Nil = 0,
    z_value_ValueTag_Int = 1,
    z_value_ValueTag_Bool = 2,
    z_value_ValueTag_Symbol = 3,
    z_value_ValueTag_Cons = 4,
    z_value_ValueTag_Builtin = 5
};
typedef enum z_value_ValueTag z_value_ValueTag;

struct z_value_ConsData;
union z_value_ValueData;
struct z_value_Value;
#ifndef ZIG_SLICE_Slice_u8
#define ZIG_SLICE_Slice_u8
typedef struct { unsigned char* ptr; usize len; } Slice_u8;
static RETR_UNUSED_FUNC Slice_u8 __make_slice_u8(unsigned char* ptr, usize len) {
    Slice_u8 s;
    s.ptr = ptr;
    s.len = len;
    return s;
}
#endif

struct z_value_ConsData {
    struct z_value_Value* car;
    struct z_value_Value* cdr;
};

union z_value_ValueData {
    i64 Int;
    int Bool;
    Slice_u8 Symbol;
    struct z_value_ConsData Cons;
    void * Builtin;
};

struct z_value_Value {
    enum z_value_ValueTag tag;
    union z_value_ValueData data;
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

struct z_value_Arena; /* opaque */

struct z_value_Arena;

ErrorUnion_Ptr_z_value_Value z_value_alloc_value(struct z_arena_LispArena*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_cons(struct z_value_Value*, struct z_value_Value*, struct z_arena_LispArena*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_int(i64, struct z_arena_LispArena*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_bool(int, struct z_arena_LispArena*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_symbol(Slice_u8, struct z_arena_LispArena*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_nil(struct z_arena_LispArena*);
ErrorUnion_Ptr_z_value_Value z_value_alloc_builtin(void *, struct z_arena_LispArena*);

#endif
