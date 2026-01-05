#include "type_system.hpp"
#include <cstdio>

#define DEFINE_GET_TYPE_FUNC(name, type_kind, sz, align_val) \
    Type* get_##name() { \
        static Type t = { type_kind, sz, align_val, {}}; \
        return &t; \
    }

DEFINE_GET_TYPE_FUNC(g_type_void,  TYPE_VOID, 0, 0)
DEFINE_GET_TYPE_FUNC(g_type_bool,  TYPE_BOOL, 4, 4)
DEFINE_GET_TYPE_FUNC(g_type_i8,    TYPE_I8,   1, 1)
DEFINE_GET_TYPE_FUNC(g_type_i16,   TYPE_I16,  2, 2)
DEFINE_GET_TYPE_FUNC(g_type_i32,   TYPE_I32,  4, 4)
DEFINE_GET_TYPE_FUNC(g_type_i64,   TYPE_I64,  8, 8)
DEFINE_GET_TYPE_FUNC(g_type_u8,    TYPE_U8,   1, 1)
DEFINE_GET_TYPE_FUNC(g_type_u16,   TYPE_U16,  2, 2)
DEFINE_GET_TYPE_FUNC(g_type_u32,   TYPE_U32,  4, 4)
DEFINE_GET_TYPE_FUNC(g_type_u64,   TYPE_U64,  8, 8)
DEFINE_GET_TYPE_FUNC(g_type_isize, TYPE_ISIZE,4, 4) // Assuming 32-bit target
DEFINE_GET_TYPE_FUNC(g_type_usize, TYPE_USIZE,4, 4) // Assuming 32-bit target
DEFINE_GET_TYPE_FUNC(g_type_f32,   TYPE_F32,  4, 4)
DEFINE_GET_TYPE_FUNC(g_type_f64,   TYPE_F64,  8, 8)

Type* resolvePrimitiveTypeName(const char* name) {
    if (strcmp(name, "void") == 0) return get_g_type_void();
    if (strcmp(name, "bool") == 0) return get_g_type_bool();
    if (strcmp(name, "i8") == 0) return get_g_type_i8();
    if (strcmp(name, "i16") == 0) return get_g_type_i16();
    if (strcmp(name, "i32") == 0) return get_g_type_i32();
    if (strcmp(name, "i64") == 0) return get_g_type_i64();
    if (strcmp(name, "u8") == 0) return get_g_type_u8();
    if (strcmp(name, "u16") == 0) return get_g_type_u16();
    if (strcmp(name, "u32") == 0) return get_g_type_u32();
    if (strcmp(name, "u64") == 0) return get_g_type_u64();
    if (strcmp(name, "isize") == 0) return get_g_type_isize();
    if (strcmp(name, "usize") == 0) return get_g_type_usize();
    if (strcmp(name, "f32") == 0) return get_g_type_f32();
    if (strcmp(name, "f64") == 0) return get_g_type_f64();
    return NULL;
}

Type* createPointerType(ArenaAllocator& arena, Type* base, bool is_const) {
    Type* ptr_type = (Type*)arena.alloc(sizeof(Type));
    ptr_type->kind = TYPE_POINTER;
    ptr_type->size = 4; // Assuming 32-bit target
    ptr_type->alignment = 4;
    ptr_type->as.pointer.base = base;
    ptr_type->as.pointer.is_const = is_const;
    return ptr_type;
}

Type* createArrayType(ArenaAllocator& arena, Type* element_type, u64 size) {
    Type* array_type = (Type*)arena.alloc(sizeof(Type));
    array_type->kind = TYPE_ARRAY;
    array_type->size = element_type->size * size;
    array_type->alignment = element_type->alignment;
    array_type->as.array.element_type = element_type;
    array_type->as.array.size = size;
    return array_type;
}

Type* createEnumType(ArenaAllocator& arena, Type* backing_type, DynamicArray<EnumMember>* members) {
    Type* enum_type = (Type*)arena.alloc(sizeof(Type));
    enum_type->kind = TYPE_ENUM;
    enum_type->size = backing_type->size;
    enum_type->alignment = backing_type->alignment;
    enum_type->as.enum_details.backing_type = backing_type;
    enum_type->as.enum_details.members = members;
    return enum_type;
}

Type* createFunctionType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type) {
    Type* func_type = (Type*)arena.alloc(sizeof(Type));
    func_type->kind = TYPE_FUNCTION;
    func_type->size = 0; // Functions don't have a size in this context
    func_type->alignment = 0;
    func_type->as.function.params = params;
    func_type->as.function.return_type = return_type;
    return func_type;
}

void typeToString(Type* type, char* buffer, size_t buffer_size) {
    if (!type) {
        snprintf(buffer, buffer_size, "(null)");
        return;
    }

    switch (type->kind) {
        case TYPE_VOID: snprintf(buffer, buffer_size, "void"); break;
        case TYPE_BOOL: snprintf(buffer, buffer_size, "bool"); break;
        case TYPE_I8:   snprintf(buffer, buffer_size, "i8"); break;
        case TYPE_I16:  snprintf(buffer, buffer_size, "i16"); break;
        case TYPE_I32:  snprintf(buffer, buffer_size, "i32"); break;
        case TYPE_I64:  snprintf(buffer, buffer_size, "i64"); break;
        case TYPE_U8:   snprintf(buffer, buffer_size, "u8"); break;
        case TYPE_U16:  snprintf(buffer, buffer_size, "u16"); break;
        case TYPE_U32:  snprintf(buffer, buffer_size, "u32"); break;
        case TYPE_U64:  snprintf(buffer, buffer_size, "u64"); break;
        case TYPE_ISIZE: snprintf(buffer, buffer_size, "isize"); break;
        case TYPE_USIZE: snprintf(buffer, buffer_size, "usize"); break;
        case TYPE_F32:  snprintf(buffer, buffer_size, "f32"); break;
        case TYPE_F64:  snprintf(buffer, buffer_size, "f64"); break;
        case TYPE_POINTER: {
            char base_type_str[64];
            typeToString(type->as.pointer.base, base_type_str, sizeof(base_type_str));
            if (type->as.pointer.is_const) {
                snprintf(buffer, buffer_size, "*const %s", base_type_str);
            } else {
                snprintf(buffer, buffer_size, "*%s", base_type_str);
            }
            break;
        }
        case TYPE_ARRAY: {
            char element_type_str[64];
            typeToString(type->as.array.element_type, element_type_str, sizeof(element_type_str));
            snprintf(buffer, buffer_size, "[%llu]%s", (unsigned long long)type->as.array.size, element_type_str);
            break;
        }
        case TYPE_ENUM: snprintf(buffer, buffer_size, "enum"); break;
        case TYPE_FUNCTION: snprintf(buffer, buffer_size, "function"); break;
        default: snprintf(buffer, buffer_size, "unknown_type"); break;
    }
}
