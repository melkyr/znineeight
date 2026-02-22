#include "type_system.hpp"
#include "memory.hpp"
#include "utils.hpp"
#include "platform.hpp"

// Using functions with static locals to avoid the static initialization order fiasco.
// This ensures that the type objects are created when they are first needed.
#define DEFINE_GET_TYPE_FUNC(name, type_kind, sz, align_val) \
    Type* get_##name() { \
        static Type t; \
        static bool initialized = false; \
        if (!initialized) { \
            t.kind = type_kind; \
            t.size = sz; \
            t.alignment = align_val; \
            t.c_name = NULL; \
            initialized = true; \
        } \
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
DEFINE_GET_TYPE_FUNC(g_type_undefined, TYPE_UNDEFINED, 0, 0)
DEFINE_GET_TYPE_FUNC(g_type_type, TYPE_TYPE, 0, 0)
DEFINE_GET_TYPE_FUNC(g_type_noreturn, TYPE_NORETURN, 0, 1)
DEFINE_GET_TYPE_FUNC(g_type_anytype, TYPE_ANYTYPE, 0, 0)

static Type* allocateType(ArenaAllocator& arena) {
    Type* t = (Type*)arena.alloc(sizeof(Type));
#ifdef MEASURE_MEMORY
    MemoryTracker::types++;
#endif
    if (t) plat_memset(t, 0, sizeof(Type));
    return t;
}

Type* createModuleType(ArenaAllocator& arena, const char* name) {
    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_MODULE;
    new_type->size = 0;
    new_type->alignment = 0;
    new_type->as.module.name = name;
    new_type->as.module.module_ptr = NULL;
    return new_type;
}

Type* createTupleType(ArenaAllocator& arena, DynamicArray<Type*>* elements) {
    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_TUPLE;
    new_type->size = 0; // Not used for runtime storage in bootstrap
    new_type->alignment = 0;
    new_type->as.tuple.elements = elements;
    return new_type;
}

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
    if (plat_strcmp(name, "noreturn") == 0) return get_g_type_noreturn();
    if (plat_strcmp(name, "anytype") == 0) return get_g_type_anytype();

    return NULL; // Not a known primitive type
}


Type* createPointerType(ArenaAllocator& arena, Type* base_type, bool is_const, bool is_many, TypeInterner* interner) {
    if (interner) {
        return interner->getPointerType(base_type, is_const, is_many);
    }

    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_POINTER;
    new_type->size = 4; // Assuming 32-bit pointers
    new_type->alignment = 4; // Assuming 32-bit pointers
    new_type->as.pointer.base = base_type;
    new_type->as.pointer.is_const = is_const;
    new_type->as.pointer.is_many = is_many;
    return new_type;
}

Type* createFunctionType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type) {
    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_FUNCTION;
    new_type->size = 0; // Functions don't have a size in the same way
    new_type->alignment = 0;
    new_type->as.function.params = params;
    new_type->as.function.return_type = return_type;
    return new_type;
}

Type* createFunctionPointerType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type) {
    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_FUNCTION_POINTER;
    new_type->size = 4;
    new_type->alignment = 4;
    new_type->as.function_pointer.param_types = params;
    new_type->as.function_pointer.return_type = return_type;
    return new_type;
}

Type* createArrayType(ArenaAllocator& arena, Type* element_type, u64 size, TypeInterner* interner) {
    if (interner) {
        return interner->getArrayType(element_type, size);
    }

    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_ARRAY;
    new_type->size = element_type->size * size;
    new_type->alignment = element_type->alignment;
    new_type->as.array.element_type = element_type;
    new_type->as.array.size = size;
    return new_type;
}

Type* createSliceType(ArenaAllocator& arena, Type* element_type, bool is_const, TypeInterner* interner) {
    if (interner) {
        return interner->getSliceType(element_type, is_const);
    }

    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_SLICE;
    new_type->size = 8; // 32-bit: pointer (4) + length (4)
    new_type->alignment = 4;
    new_type->as.slice.element_type = element_type;
    new_type->as.slice.is_const = is_const;
    return new_type;
}

Type* createStructType(ArenaAllocator& arena, DynamicArray<StructField>* fields, const char* name) {
    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_STRUCT;
    new_type->size = 0; // Will be calculated by calculateStructLayout
    new_type->alignment = 1; // Will be calculated by calculateStructLayout
    new_type->as.struct_details.name = name;
    new_type->as.struct_details.fields = fields;
    return new_type;
}

Type* createUnionType(ArenaAllocator& arena, DynamicArray<StructField>* fields, const char* name) {
    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_UNION;
    new_type->size = 0; // Should be max field size
    new_type->alignment = 1; // Should be max field alignment
    new_type->as.struct_details.name = name;
    new_type->as.struct_details.fields = fields;

    // Calculate union size and alignment
    size_t max_size = 0;
    size_t max_align = 1;
    for (size_t i = 0; i < fields->length(); ++i) {
        StructField& field = (*fields)[i];
        if (field.type->size > max_size) max_size = field.type->size;
        if (field.type->alignment > max_align) max_align = field.type->alignment;
        field.offset = 0; // All union fields are at offset 0
    }
    // Pad total size to max_align
    if (max_size % max_align != 0) {
        max_size += (max_align - (max_size % max_align));
    }
    new_type->size = max_size;
    new_type->alignment = max_align;

    return new_type;
}

Type* createErrorUnionType(ArenaAllocator& arena, Type* payload, Type* error_set, bool is_inferred) {
    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_ERROR_UNION;
    new_type->size = 8; // Placeholder: error union size is usually tag + payload
    new_type->alignment = 4;
    new_type->as.error_union.payload = payload;
    new_type->as.error_union.error_set = error_set;
    new_type->as.error_union.is_inferred = is_inferred;
    return new_type;
}

Type* createOptionalType(ArenaAllocator& arena, Type* payload, TypeInterner* interner) {
    if (interner) {
        return interner->getOptionalType(payload);
    }

    Type* new_type = allocateType(arena);
    new_type->kind = TYPE_OPTIONAL;
    new_type->size = 8; // Placeholder: optional size is usually tag + payload
    new_type->alignment = 4;
    new_type->as.optional.payload = payload;
    return new_type;
}

Type* createErrorSetType(ArenaAllocator& arena, const char* name, DynamicArray<const char*>* tags, bool is_anonymous) {
    Type* new_type = allocateType(arena);
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
    Type* new_type = allocateType(arena);
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

// --- TypeInterner Implementation ---

TypeInterner::TypeInterner(ArenaAllocator& arena)
    : arena_(arena), unique_count(0), dedupe_count(0) {
    for (int i = 0; i < 256; i++) {
        buckets[i] = NULL;
    }
}

u32 TypeInterner::hashType(TypeKind kind, void* p1, u64 v1) {
    u32 h = (u32)kind;
    h ^= (u32)((size_t)p1 & 0xFFFFFFFF);
    h ^= (u32)(v1 & 0xFFFFFFFF);
    return h % 256;
}

Type* TypeInterner::getPointerType(Type* base_type, bool is_const, bool is_many) {
    u32 h = hashType(TYPE_POINTER, base_type, (u64)is_const | ((u64)is_many << 8));
    for (Entry* e = buckets[h]; e; e = e->next) {
        if (e->type->kind == TYPE_POINTER &&
            e->type->as.pointer.base == base_type &&
            e->type->as.pointer.is_const == is_const &&
            e->type->as.pointer.is_many == is_many) {
            dedupe_count++;
            return e->type;
        }
    }

    Type* t = createPointerType(arena_, base_type, is_const, is_many, NULL);
    Entry* e = (Entry*)arena_.alloc(sizeof(Entry));
    e->type = t;
    e->next = buckets[h];
    buckets[h] = e;
    unique_count++;
    return t;
}

Type* TypeInterner::getArrayType(Type* element_type, u64 size) {
    u32 h = hashType(TYPE_ARRAY, element_type, size);
    for (Entry* e = buckets[h]; e; e = e->next) {
        if (e->type->kind == TYPE_ARRAY &&
            e->type->as.array.element_type == element_type &&
            e->type->as.array.size == size) {
            dedupe_count++;
            return e->type;
        }
    }

    Type* t = createArrayType(arena_, element_type, size, NULL);
    Entry* e = (Entry*)arena_.alloc(sizeof(Entry));
    e->type = t;
    e->next = buckets[h];
    buckets[h] = e;
    unique_count++;
    return t;
}

Type* TypeInterner::getSliceType(Type* element_type, bool is_const) {
    u32 h = hashType(TYPE_SLICE, element_type, is_const ? 1 : 0);
    for (Entry* e = buckets[h]; e; e = e->next) {
        if (e->type->kind == TYPE_SLICE &&
            e->type->as.slice.element_type == element_type &&
            e->type->as.slice.is_const == is_const) {
            dedupe_count++;
            return e->type;
        }
    }

    Type* t = createSliceType(arena_, element_type, is_const, NULL);
    Entry* e = (Entry*)arena_.alloc(sizeof(Entry));
    e->type = t;
    e->next = buckets[h];
    buckets[h] = e;
    unique_count++;
    return t;
}

Type* TypeInterner::getOptionalType(Type* payload) {
    u32 h = hashType(TYPE_OPTIONAL, payload, 0);
    for (Entry* e = buckets[h]; e; e = e->next) {
        if (e->type->kind == TYPE_OPTIONAL &&
            e->type->as.optional.payload == payload) {
            dedupe_count++;
            return e->type;
        }
    }

    Type* t = createOptionalType(arena_, payload, NULL);
    Entry* e = (Entry*)arena_.alloc(sizeof(Entry));
    e->type = t;
    e->next = buckets[h];
    buckets[h] = e;
    unique_count++;
    return t;
}

bool isTypeComplete(Type* type) {
    if (!type) return false;
    switch (type->kind) {
        case TYPE_VOID:
        case TYPE_BOOL:
        case TYPE_I8: case TYPE_I16: case TYPE_I32: case TYPE_I64:
        case TYPE_U8: case TYPE_U16: case TYPE_U32: case TYPE_U64:
        case TYPE_ISIZE: case TYPE_USIZE:
        case TYPE_F32: case TYPE_F64:
        case TYPE_NORETURN: return true;
        case TYPE_POINTER:
        case TYPE_NULL:
        case TYPE_ENUM:
            return true;
        case TYPE_ARRAY:
            return isTypeComplete(type->as.array.element_type);
        case TYPE_SLICE:
            return true; // Slices are always complete (size 8, align 4)
        case TYPE_STRUCT:
        case TYPE_UNION:
            // calculateStructLayout sets size > 0 for non-empty structs
            // Zig allows 0-sized structs, but they are "complete" once layout is calculated.
            // For bootstrap, we'll consider it complete if it has a valid fields pointer
            // and we've at least attempted layout.
            // A simple proxy for "layout calculated" in this compiler is size > 0
            // OR it being a explicitly defined empty struct.
            // Given calculateStructLayout is called after fields are processed,
            // let's use a heuristic: if it's a struct/union, it must have fields (even if empty)
            // and calculateStructLayout must have been called.
            // Since calculateStructLayout sets alignment >= 1, we can check that.
            return type->alignment >= 1 && type->as.struct_details.fields != NULL;
        default:
            return false;
    }
}

static void typeToStringInternal(Type* type, char*& current, size_t& remaining) {
    if (!type || remaining == 0) return;

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
            if (type->as.pointer.is_many) {
                safe_append(current, remaining, "[*]");
            } else {
                safe_append(current, remaining, "*");
            }
            if (type->as.pointer.is_const) {
                safe_append(current, remaining, "const ");
            }
            typeToStringInternal(type->as.pointer.base, current, remaining);
            break;
        }
        case TYPE_ARRAY: {
            safe_append(current, remaining, "[");
            // Note: This is a simplified itoa; a proper one would be better.
            if (remaining > 21) {
                char size_buf[21];
                plat_u64_to_string(type->as.array.size, size_buf, sizeof(size_buf));
                safe_append(current, remaining, size_buf);
            }
            safe_append(current, remaining, "]");
            typeToStringInternal(type->as.array.element_type, current, remaining);
            break;
        }
        case TYPE_SLICE: {
            safe_append(current, remaining, "[]");
            if (type->as.slice.is_const) {
                safe_append(current, remaining, "const ");
            }
            typeToStringInternal(type->as.slice.element_type, current, remaining);
            break;
        }
        case TYPE_FUNCTION_POINTER: {
            safe_append(current, remaining, "fn(");
            if (type->as.function_pointer.param_types) {
                for (size_t i = 0; i < type->as.function_pointer.param_types->length(); ++i) {
                    typeToStringInternal((*type->as.function_pointer.param_types)[i], current, remaining);
                    if (i < type->as.function_pointer.param_types->length() - 1) {
                        safe_append(current, remaining, ", ");
                    }
                }
            }
            safe_append(current, remaining, ") ");
            typeToStringInternal(type->as.function_pointer.return_type, current, remaining);
            break;
        }
        case TYPE_FUNCTION: {
            safe_append(current, remaining, "fn(");
            if (type->as.function.params) {
                for (size_t i = 0; i < type->as.function.params->length(); ++i) {
                    typeToStringInternal((*type->as.function.params)[i], current, remaining);
                    if (i < type->as.function.params->length() - 1) {
                        safe_append(current, remaining, ", ");
                    }
                }
            }
            safe_append(current, remaining, ") ");
            typeToStringInternal(type->as.function.return_type, current, remaining);
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
        case TYPE_UNION:
            safe_append(current, remaining, "union ");
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
                typeToStringInternal(type->as.error_union.error_set, current, remaining);
                safe_append(current, remaining, "!");
            }
            typeToStringInternal(type->as.error_union.payload, current, remaining);
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
            typeToStringInternal(type->as.optional.payload, current, remaining);
            break;
        }
        case TYPE_TYPE:    safe_append(current, remaining, "type"); break;
        case TYPE_NORETURN: safe_append(current, remaining, "noreturn"); break;
        case TYPE_ANYTYPE: safe_append(current, remaining, "anytype"); break;
        case TYPE_MODULE:
            safe_append(current, remaining, "module ");
            safe_append(current, remaining, type->as.module.name);
            break;
        case TYPE_INTEGER_LITERAL: safe_append(current, remaining, "comptime_int"); break;
        default:
            safe_append(current, remaining, "unknown");
            break;
    }
}

void typeToString(Type* type, char* buffer, size_t buffer_size) {
    if (!type || buffer_size == 0) {
        if (buffer_size > 0) buffer[0] = '\0';
        return;
    }

    char* current = buffer;
    size_t remaining = buffer_size;
    typeToStringInternal(type, current, remaining);
}

bool areTypesEqual(Type* a, Type* b) {
    if (a == b) return true;
    if (!a || !b) return false;
    if (a->kind != b->kind) {
        // One exception: TYPE_FUNCTION and TYPE_FUNCTION_POINTER are structurally equal
        // if their signatures match. But this function is for GENERAL type equality.
        // Actually, for pointers to functions, they should both be TYPE_FUNCTION_POINTER.
        return false;
    }

    switch (a->kind) {
        case TYPE_POINTER:
            return a->as.pointer.is_const == b->as.pointer.is_const &&
                   a->as.pointer.is_many == b->as.pointer.is_many &&
                   areTypesEqual(a->as.pointer.base, b->as.pointer.base);

        case TYPE_ARRAY:
            return a->as.array.size == b->as.array.size &&
                   areTypesEqual(a->as.array.element_type, b->as.array.element_type);

        case TYPE_SLICE:
            return a->as.slice.is_const == b->as.slice.is_const &&
                   areTypesEqual(a->as.slice.element_type, b->as.slice.element_type);

        case TYPE_OPTIONAL:
            return areTypesEqual(a->as.optional.payload, b->as.optional.payload);

        case TYPE_FUNCTION:
            return signaturesMatch(a->as.function.params, a->as.function.return_type,
                                  b->as.function.params, b->as.function.return_type);
        case TYPE_FUNCTION_POINTER:
            return signaturesMatch(a->as.function_pointer.param_types, a->as.function_pointer.return_type,
                                  b->as.function_pointer.param_types, b->as.function_pointer.return_type);

        case TYPE_STRUCT:
        case TYPE_UNION:
        case TYPE_ENUM:
            return false;

        default:
            return true;
    }
}

bool signaturesMatch(DynamicArray<Type*>* a_params, Type* a_return, DynamicArray<Type*>* b_params, Type* b_return) {
    if (!areTypesEqual(a_return, b_return)) {
        return false;
    }

    if (!a_params && !b_params) return true;
    if (!a_params || !b_params) return false;

    if (a_params->length() != b_params->length()) {
        return false;
    }

    for (size_t i = 0; i < a_params->length(); ++i) {
        if (!areTypesEqual((*a_params)[i], (*b_params)[i])) {
            return false;
        }
    }

    return true;
}
