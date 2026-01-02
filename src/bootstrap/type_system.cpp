#include "type_system.hpp"
#include "memory.hpp"
#include <cstdio> // For sprintf
#include <cstring> // For strcmp

// Statically define all the primitive types.
// This ensures that we only have one instance of each primitive type,
// saving memory and allowing for simple pointer comparisons.

Type g_type_void = { TYPE_VOID, 0, 0 };
Type g_type_bool = { TYPE_BOOL, 1, 1 };

Type g_type_i8  = { TYPE_I8,  1, 1 };
Type g_type_i16 = { TYPE_I16, 2, 2 };
Type g_type_i32 = { TYPE_I32, 4, 4 };
Type g_type_i64 = { TYPE_I64, 8, 8 };

Type g_type_u8  = { TYPE_U8,  1, 1 };
Type g_type_u16 = { TYPE_U16, 2, 2 };
Type g_type_u32 = { TYPE_U32, 4, 4 };
Type g_type_u64 = { TYPE_U64, 8, 8 };

Type g_type_isize = { TYPE_ISIZE, 4, 4 }; // Assuming 32-bit target
Type g_type_usize = { TYPE_USIZE, 4, 4 }; // Assuming 32-bit target

Type g_type_f32 = { TYPE_F32, 4, 4 };
Type g_type_f64 = { TYPE_F64, 8, 8 };


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

Type* createPointerType(ArenaAllocator& arena, Type* base_type, bool is_const) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
    new_type->kind = TYPE_POINTER;
    new_type->size = 4; // Assuming 32-bit pointers
    new_type->alignment = 4; // Assuming 32-bit pointers
    new_type->as.pointer.base = base_type;
    new_type->as.pointer.is_const = is_const;
    return new_type;
}

Type* createFunctionType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type) {
    Type* new_type = (Type*)arena.alloc(sizeof(Type));
    new_type->kind = TYPE_FUNCTION;
    new_type->size = 0; // Functions don't have a size in the same way
    new_type->alignment = 0;
    new_type->as.function.params = params;
    new_type->as.function.return_type = return_type;
    return new_type;
}

void typeToString(Type* type, char* buffer, size_t buffer_size) {
    if (!type) {
        snprintf(buffer, buffer_size, "(null)");
        return;
    }

    const char* primitive_name = NULL;
    switch (type->kind) {
        case TYPE_VOID: primitive_name = "void"; break;
        case TYPE_BOOL: primitive_name = "bool"; break;
        case TYPE_I8:   primitive_name = "i8";   break;
        case TYPE_I16:  primitive_name = "i16";  break;
        case TYPE_I32:  primitive_name = "i32";  break;
        case TYPE_I64:  primitive_name = "i64";  break;
        case TYPE_U8:   primitive_name = "u8";   break;
        case TYPE_U16:  primitive_name = "u16";  break;
        case TYPE_U32:  primitive_name = "u32";  break;
        case TYPE_U64:  primitive_name = "u64";  break;
        case TYPE_ISIZE:primitive_name = "isize";break;
        case TYPE_USIZE:primitive_name = "usize";break;
        case TYPE_F32:  primitive_name = "f32";  break;
        case TYPE_F64:  primitive_name = "f64";  break;
        case TYPE_POINTER: {
            char base_name[64];
            typeToString(type->as.pointer.base, base_name, sizeof(base_name));
            if (type->as.pointer.is_const) {
                snprintf(buffer, buffer_size, "*const %s", base_name);
            } else {
                snprintf(buffer, buffer_size, "*%s", base_name);
            }
            return;
        }
        case TYPE_FUNCTION: {
            char return_type_str[64];
            typeToString(type->as.function.return_type, return_type_str, sizeof(return_type_str));

            size_t offset = snprintf(buffer, buffer_size, "fn(");

            if (type->as.function.params) {
                for (size_t i = 0; i < type->as.function.params->length(); ++i) {
                    if (offset >= buffer_size) break;
                    char param_type_str[64];
                    typeToString((*type->as.function.params)[i], param_type_str, sizeof(param_type_str));
                    offset += snprintf(buffer + offset, buffer_size - offset, "%s", param_type_str);
                    if (i < type->as.function.params->length() - 1) {
                        if (offset < buffer_size) {
                            offset += snprintf(buffer + offset, buffer_size - offset, ", ");
                        }
                    }
                }
            }

            if (offset < buffer_size) {
                snprintf(buffer + offset, buffer_size - offset, ") -> %s", return_type_str);
            }
            return;
        }
        default: primitive_name = "unknown"; break;
    }

    snprintf(buffer, buffer_size, "%s", primitive_name);
}
