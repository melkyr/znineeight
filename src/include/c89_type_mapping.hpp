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
    { TYPE_F64, "double" }
};

/**
 * @brief Checks if a given type is compatible with the C89 subset.
 *
 * This function validates that a type is either a whitelisted primitive type
 * (as defined in c89_type_map) or a single-level pointer to one of those
 * primitive types. It rejects multi-level pointers and other complex types.
 *
 * @param type A pointer to the Type object to check.
 * @return True if the type is C89-compatible, false otherwise.
 */
static inline bool is_c89_compatible(Type* type) {
    if (!type) {
        return false;
    }

    // Handle pointers: must be a single-level pointer to a whitelisted primitive.
    if (type->kind == TYPE_POINTER) {
        Type* base_type = type->as.pointer.base;
        if (!base_type) {
            return false; // Invalid pointer to nothing.
        }
        // Reject multi-level pointers (e.g., **i32).
        if (base_type->kind == TYPE_POINTER) {
            return false;
        }
        // The base type must be a whitelisted primitive.
        // Fall through to the primitive check below.
        type = base_type;
    }

    // Check for whitelisted primitive types.
    const size_t map_size = sizeof(c89_type_map) / sizeof(c89_type_map[0]);
    for (size_t i = 0; i < map_size; ++i) {
        if (type->kind == c89_type_map[i].zig_type_kind) {
            return true;
        }
    }

    return false;
}

#endif // C89_TYPE_MAPPING_HPP
