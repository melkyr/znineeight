#include "type_system.hpp"
#include "memory.hpp"
#include "utils.hpp"
#include "platform.hpp"

// Using functions with static locals to avoid the static initialization order fiasco.
// This ensures that the type objects are created when they are first needed.
#define DEFINE_GET_TYPE_FUNC(name, type_kind, sz, align_val) \
    Type* get_##name() { \
        static Type t = { type_kind, sz, align_val, {} }; \
        return &t; \
    }

DEFINE_GET_TYPE_FUNC(g_type_void, TYPE_VOID, 0, 0)
DEFINE_GET_TYPE_FUNC(g_type_bool, TYPE_BOOL, 4, 4)
DEFINE_GET_TYPE_FUNC(g_type_i8,   TYPE_I8,   1, 1)
DEFINE_GET_TYPE_FUNC(g_type_i16,  TYPE_I16,  2, 2)
DEFINE_GET_TYPE_FUNC(g_type_i32,  TYPE_I32,  4, 4)
DEFINE_GET_TYPE_FUNC(g_type_i64,  TYPE_I64,  8, 8)
DEFINE_GET_TYPE_FUNC(g_type_u8,   TYPE_U8,   1, 1)
DEFINE_GET_TYPE_FUNC(g_type_u16,  TYPE_U16,  2, 2)
DEFINE_GET_TYPE_FUNC(g_type_u32,  TYPE_U32,  4, 4)
DEFINE_GET_TYPE_FUNC(g_type_u64,  TYPE_U64,  8, 8)
DEFINE_GET_TYPE_FUNC(g_type_isize,TYPE_ISIZE,4, 4) // Assuming 32-bit target
DEFINE_GET_TYPE_FUNC(g_type_usize,TYPE_USIZE,4, 4) // Assuming 32-bit target
DEFINE_GET_TYPE_FUNC(g_type_f32,  TYPE_F32,  4, 4)
DEFINE_GET_TYPE_FUNC(g_type_f64,  TYPE_F64,  8, 8)

DEFINE_GET_TYPE_FUNC(g_type_null, TYPE_NULL, 0, 0)
DEFINE_GET_TYPE_FUNC(g_type_type, TYPE_TYPE, 0, 0)
DEFINE_GET_TYPE_FUNC(g_type_anytype, TYPE_ANYTYPE, 0, 0)

Type* resolvePrimitiveTypeName(const char* name) {
    if (plat_strcmp(name, "void") == 0) return get_g_type_void();
    if (plat_strcmp(name, "bool") == 0) return get_g_type_bool();
    if (plat_strcmp(name, "i8") == 0) return get_g_type_i8();
    if (plat_strcmp(name, "i16") == 0) return get_g_type_i16();
    if (plat_strcmp(name, "i32") == 0) return get_g_type_i32();
    if (plat_strcmp(name, "i64") == 0) return get_g_type_i64();
    if (plat_strcmp(name, "u8") == 0) return get_g_type_u8();
    if (plat_strcmp(name, "u16") == 0) return get_g_type_u16();
    if (plat_strcmp(name, "u32") == 0) return get_g_type_u32();
    if (plat_strcmp(name, "u64") == 0) return get_g_type_u64();
    if (plat_strcmp(name, "isize") == 0) return get_g_type_isize();
    if (plat_strcmp(name, "usize") == 0) return get_g_type_usize();
    if (plat_strcmp(name, "f32") == 0) return get_g_type_f32();
    if (plat_strcmp(name, "f64") == 0) return get_g_type_f64();
    if (plat_strcmp(name, "type") == 0) return get_g_type_type();
    if (plat_strcmp(name, "anytype") == 0) return get_g_type_anytype();

    return NULL; // Not a known primitive type
}

Type* createPointerType(ArenaAllocator& arena, Type* base_type, bool is_const) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_POINTER;
    new_type->size = 4; // Assuming 32-bit pointers
    new_type->alignment = 4; // Assuming 32-bit pointers
    new_type->as.pointer.base = base_type;
    new_type->as.pointer.is_const = is_const;
    return new_type;
}

Type* createFunctionType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_FUNCTION;
    new_type->size = 0; // Functions don't have a size in the same way
    new_type->alignment = 0;
    new_type->as.function.params = params;
    new_type->as.function.return_type = return_type;
    return new_type;
}

Type* createArrayType(ArenaAllocator& arena, Type* element_type, u64 size) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_ARRAY;
    new_type->size = element_type->size * size;
    new_type->alignment = element_type->alignment;
    new_type->as.array.element_type = element_type;
    new_type->as.array.size = size;
    return new_type;
}

Type* createStructType(ArenaAllocator& arena, DynamicArray<StructField>* fields, const char* name) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_STRUCT;
    new_type->size = 0; // Will be calculated by calculateStructLayout
    new_type->alignment = 1; // Will be calculated by calculateStructLayout
    new_type->as.struct_details.name = name;
    new_type->as.struct_details.fields = fields;
    return new_type;
}

Type* createErrorUnionType(ArenaAllocator& arena, Type* payload, Type* error_set, bool is_inferred) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_ERROR_UNION;
    new_type->size = 8; // Placeholder: error union size is usually tag + payload
    new_type->alignment = 4;
    new_type->as.error_union.payload = payload;
    new_type->as.error_union.error_set = error_set;
    new_type->as.error_union.is_inferred = is_inferred;
    return new_type;
}

Type* createOptionalType(ArenaAllocator& arena, Type* payload) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_OPTIONAL;
    new_type->size = 8; // Placeholder: optional size is usually tag + payload
    new_type->alignment = 4;
    new_type->as.optional.payload = payload;
    return new_type;
}

Type* createErrorSetType(ArenaAllocator& arena, const char* name, DynamicArray<const char*>* tags, bool is_anonymous) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_ERROR_SET;
    new_type->size = 2; // Placeholder: error sets are typically 16-bit integers
    new_type->alignment = 2;
    new_type->as.error_set.name = name;
    new_type->as.error_set.tags = tags;
    new_type->as.error_set.is_anonymous = is_anonymous;
    return new_type;
}

void calculateStructLayout(Type* struct_type) {
    if (struct_type->kind != TYPE_STRUCT) return;

    DynamicArray<StructField>* fields = struct_type->as.struct_details.fields;
    size_t current_offset = 0;
    size_t max_alignment = 1;

    for (size_t i = 0; i < fields->length(); ++i) {
        StructField& field = (*fields)[i];
        size_t field_alignment = field.type->alignment;
        if (field_alignment == 0) field_alignment = 1;

        // Align current_offset to field_alignment
        if (current_offset % field_alignment != 0) {
            current_offset += (field_alignment - (current_offset % field_alignment));
        }

        field.offset = current_offset;
        field.size = field.type->size;
        field.alignment = field_alignment;

        current_offset += field.size;
        if (field_alignment > max_alignment) {
            max_alignment = field_alignment;
        }
    }

    // Final struct alignment and padding
    if (current_offset % max_alignment != 0) {
        current_offset += (max_alignment - (current_offset % max_alignment));
    }

    struct_type->size = current_offset;
    struct_type->alignment = max_alignment;
}

Type* createEnumType(ArenaAllocator& arena, const char* name, Type* backing_type, DynamicArray<EnumMember>* members, i64 min_val, i64 max_val) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    new_type->kind = TYPE_ENUM;
    new_type->size = backing_type->size;
    new_type->alignment = backing_type->alignment;
    new_type->as.enum_details.name = name;
    new_type->as.enum_details.backing_type = backing_type;
    new_type->as.enum_details.members = members;
    new_type->as.enum_details.min_value = min_val;
    new_type->as.enum_details.max_value = max_val;
    return new_type;
}

void typeToString(Type* type, char* buffer, size_t buffer_size) {
    if (!type || buffer_size == 0) {
        if (buffer_size > 0) buffer[0] = '\0';
        return;
    }

    char* current = buffer;
    size_t remaining = buffer_size;

    switch (type->kind) {
        case TYPE_VOID:  safe_append(current, remaining, "void"); break;
        case TYPE_BOOL:  safe_append(current, remaining, "bool"); break;
        case TYPE_I8:    safe_append(current, remaining, "i8"); break;
        case TYPE_I16:   safe_append(current, remaining, "i16"); break;
        case TYPE_I32:   safe_append(current, remaining, "i32"); break;
        case TYPE_I64:   safe_append(current, remaining, "i64"); break;
        case TYPE_U8:    safe_append(current, remaining, "u8"); break;
        case TYPE_U16:   safe_append(current, remaining, "u16"); break;
        case TYPE_U32:   safe_append(current, remaining, "u32"); break;
        case TYPE_U64:   safe_append(current, remaining, "u64"); break;
        case TYPE_ISIZE: safe_append(current, remaining, "isize"); break;
        case TYPE_USIZE: safe_append(current, remaining, "usize"); break;
        case TYPE_F32:   safe_append(current, remaining, "f32"); break;
        case TYPE_F64:   safe_append(current, remaining, "f64"); break;
        case TYPE_NULL:  safe_append(current, remaining, "null"); break;
        case TYPE_POINTER: {
            if (type->as.pointer.is_const) {
                safe_append(current, remaining, "*const ");
            } else {
                safe_append(current, remaining, "*");
            }
            typeToString(type->as.pointer.base, current, remaining);
            break;
        }
        case TYPE_ARRAY: {
            safe_append(current, remaining, "[");
            // Note: This is a simplified itoa; a proper one would be better.
            if (remaining > 11) {
                char size_buf[21];
                simple_itoa(type->as.array.size, size_buf, sizeof(size_buf));
                safe_append(current, remaining, size_buf);
            }
            safe_append(current, remaining, "]");
            typeToString(type->as.array.element_type, current, remaining);
            break;
        }
        case TYPE_FUNCTION: {
            safe_append(current, remaining, "fn(");
            if (type->as.function.params) {
                for (size_t i = 0; i < type->as.function.params->length(); ++i) {
                    typeToString((*type->as.function.params)[i], current, remaining);
                    if (i < type->as.function.params->length() - 1) {
                        safe_append(current, remaining, ", ");
                    }
                }
            }
            safe_append(current, remaining, ") -> ");
            typeToString(type->as.function.return_type, current, remaining);
            break;
        }
        case TYPE_ENUM:
            safe_append(current, remaining, "enum");
            break;
        case TYPE_STRUCT:
            safe_append(current, remaining, "struct ");
            if (type->as.struct_details.name) {
                safe_append(current, remaining, type->as.struct_details.name);
            } else {
                safe_append(current, remaining, "{...}");
            }
            break;
        case TYPE_ERROR_UNION: {
            if (type->as.error_union.is_inferred) {
                safe_append(current, remaining, "!");
            } else {
                typeToString(type->as.error_union.error_set, current, remaining);
                safe_append(current, remaining, "!");
            }
            typeToString(type->as.error_union.payload, current, remaining);
            break;
        }
        case TYPE_ERROR_SET: {
            if (type->as.error_set.name) {
                safe_append(current, remaining, type->as.error_set.name);
            } else {
                safe_append(current, remaining, "error{...}");
            }
            break;
        }
        case TYPE_OPTIONAL: {
            safe_append(current, remaining, "?");
            typeToString(type->as.optional.payload, current, remaining);
            break;
        }
        case TYPE_TYPE:    safe_append(current, remaining, "type"); break;
        case TYPE_ANYTYPE: safe_append(current, remaining, "anytype"); break;
        default:
            safe_append(current, remaining, "unknown");
            break;
    }
}
