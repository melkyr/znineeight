#include "type_system.hpp"
#include "memory.hpp"
#include <cstring> // For strcmp

// Statically define all the primitive types.
// This ensures that we only have one instance of each primitive type,
// saving memory and allowing for simple pointer comparisons.

static Type g_type_void = { TYPE_VOID, 0, 0 };
static Type g_type_bool = { TYPE_BOOL, 1, 1 };

static Type g_type_i8  = { TYPE_I8,  1, 1 };
static Type g_type_i16 = { TYPE_I16, 2, 2 };
static Type g_type_i32 = { TYPE_I32, 4, 4 };
static Type g_type_i64 = { TYPE_I64, 8, 8 };

static Type g_type_u8  = { TYPE_U8,  1, 1 };
static Type g_type_u16 = { TYPE_U16, 2, 2 };
static Type g_type_u32 = { TYPE_U32, 4, 4 };
static Type g_type_u64 = { TYPE_U64, 8, 8 };

static Type g_type_isize = { TYPE_ISIZE, 4, 4 }; // Assuming 32-bit target
static Type g_type_usize = { TYPE_USIZE, 4, 4 }; // Assuming 32-bit target

static Type g_type_f32 = { TYPE_F32, 4, 4 };
static Type g_type_f64 = { TYPE_F64, 8, 8 };


Type* resolvePrimitiveTypeName(const char* name) {
    if (strcmp(name, "void") == 0) return &g_type_void;
    if (strcmp(name, "bool") == 0) return &g_type_bool;
    if (strcmp(name, "i8") == 0) return &g_type_i8;
    if (strcmp(name, "i16") == 0) return &g_type_i16;
    if (strcmp(name, "i32") == 0) return &g_type_i32;
    if (strcmp(name, "i64") == 0) return &g_type_i64;
    if (strcmp(name, "u8") == 0) return &g_type_u8;
    if (strcmp(name, "u16") == 0) return &g_type_u16;
    if (strcmp(name, "u32") == 0) return &g_type_u32;
    if (strcmp(name, "u64") == 0) return &g_type_u64;
    if (strcmp(name, "isize") == 0) return &g_type_isize;
    if (strcmp(name, "usize") == 0) return &g_type_usize;
    if (strcmp(name, "f32") == 0) return &g_type_f32;
    if (strcmp(name, "f64") == 0) return &g_type_f64;

    return NULL; // Not a known primitive type
}

Type* createPointerType(ArenaAllocator& arena, Type* base_type) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
    new_type->kind = TYPE_POINTER;
    new_type->size = 4; // Assuming 32-bit pointers
    new_type->alignment = 4; // Assuming 32-bit pointers
    new_type->as.pointer.base = base_type;
    return new_type;
}
