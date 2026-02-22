#ifndef C89_TYPE_MAPPING_HPP
#define C89_TYPE_MAPPING_HPP

#include "type_system.hpp"

/**
 * @struct TypeMapping
 * @brief Maps a RetroZig TypeKind to its C89 string equivalent.
 */
struct TypeMapping {
    TypeKind zig_type_kind;
    const char* c89_type_name;
};

/**
 * @var c89_type_map
 * @brief A static table mapping RetroZig's primitive types to their C89 equivalents.
 */
static const TypeMapping c89_type_map[] = {
    { TYPE_VOID, "void" },
    { TYPE_BOOL, "int" }, // C89 uses int for boolean logic
    { TYPE_I8, "signed char" },
    { TYPE_I16, "short" },
    { TYPE_I32, "int" },
    { TYPE_I64, "__int64" }, // MSVC 6.0 specific
    { TYPE_U8, "unsigned char" },
    { TYPE_U16, "unsigned short" },
    { TYPE_U32, "unsigned int" },
    { TYPE_U64, "unsigned __int64" }, // MSVC 6.0 specific
    { TYPE_F32, "float" },
    { TYPE_F64, "double" },
    { TYPE_ISIZE, "int" },
    { TYPE_USIZE, "unsigned int" },
    { TYPE_NORETURN, "void" } // noreturn return type maps to void in C89
};

/**
 * @brief Checks if a given type is compatible with the bootstrap compiler's C89 subset.
 *
 * This function validates that a type adheres to bootstrap constraints. It accepts:
 * - Whitelisted primitive types (as defined in c89_type_map).
 * - Single-level pointers to whitelisted primitive types.
 * - Function types, provided their parameters and return types are also C89-compatible.
 * - Struct and Enum types (relying on TypeChecker for internal field validation).
 *
 * @param type A pointer to the Type object to check.
 * @return True if the type is C89-compatible, false otherwise.
 */
static inline bool is_c89_compatible(Type* type) {
    if (!type) {
        return false;
    }

    switch (type->kind) {
        case TYPE_POINTER: {
            Type* base_type = type->as.pointer.base;
            // A pointer is compatible only if its base type is a compatible type.
            // We check this by recursively calling is_c89_compatible.
            return is_c89_compatible(base_type);
        }

        case TYPE_FUNCTION_POINTER: {
            if (!type->as.function_pointer.param_types || !type->as.function_pointer.return_type) {
                return false;
            }
            if (!is_c89_compatible(type->as.function_pointer.return_type)) {
                return false;
            }
            for (size_t i = 0; i < type->as.function_pointer.param_types->length(); ++i) {
                if (!is_c89_compatible((*type->as.function_pointer.param_types)[i])) {
                    return false;
                }
            }
            return true;
        }

        case TYPE_FUNCTION: {
            // Check for uninitialized union members.
            if (!type->as.function.params || !type->as.function.return_type) {
                return false;
            }

            // Rule: Return type must be valid, C89-compatible, and not a function itself.
            Type* return_type = type->as.function.return_type;
            if (return_type->kind == TYPE_FUNCTION || !is_c89_compatible(return_type)) {
                return false;
            }

            // Rule: All parameter types must be valid, C89-compatible, and not functions themselves.
            for (size_t i = 0; i < type->as.function.params->length(); ++i) {
                Type* param_type = (*type->as.function.params)[i];
                if (!param_type || param_type->kind == TYPE_FUNCTION || !is_c89_compatible(param_type)) {
                    return false;
                }
            }

            return true;
        }

        case TYPE_ARRAY: {
            // An array is compatible if its element type is compatible.
            // Use an iterative approach to find the base primitive type.
            Type* current_type = type;
            while (current_type && current_type->kind == TYPE_ARRAY) {
                current_type = current_type->as.array.element_type;
            }
            // After the loop, check the final non-array base type.
            return is_c89_compatible(current_type);
        }

        case TYPE_SLICE:
            return is_c89_compatible(type->as.slice.element_type);

        case TYPE_ERROR_UNION:
            return is_c89_compatible(type->as.error_union.payload);

        case TYPE_ERROR_SET:
            return true;

        case TYPE_STRUCT:
        case TYPE_UNION:
        case TYPE_ENUM:
            return true;

        default: {
            // Check for whitelisted primitive types.
            const size_t map_size = sizeof(c89_type_map) / sizeof(c89_type_map[0]);
            for (size_t i = 0; i < map_size; ++i) {
                if (type->kind == c89_type_map[i].zig_type_kind) {
                    return true;
                }
            }
            // All other types (e.g., isize, array, etc.) are not compatible by default.
            return false;
        }
    }
}

#endif // C89_TYPE_MAPPING_HPP
