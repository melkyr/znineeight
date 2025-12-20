#ifndef TYPE_SYSTEM_HPP
#define TYPE_SYSTEM_HPP

#include "common.hpp"

// Forward-declare Type for the pointer union member
struct Type;

/**
 * @enum TypeKind
 * @brief Defines the fundamental kinds of types in the bootstrap type system.
 *
 * This enum is limited to types that have a direct or straightforward mapping
 * to C89 to support the bootstrap compiler's code generation target.
 */
enum TypeKind {
    TYPE_VOID,
    TYPE_BOOL,

    // Integer Types
    TYPE_I8,
    TYPE_I16,
    TYPE_I32,
    TYPE_I64,
    TYPE_U8,
    TYPE_U16,
    TYPE_U32,
    TYPE_U64,

    // Platform-dependent Integer Types
    TYPE_ISIZE, // Maps to i32 on 32-bit target
    TYPE_USIZE, // Maps to u32 on 32-bit target

    // Floating-Point Types
    TYPE_F32,
    TYPE_F64,

    // Complex Types
    TYPE_POINTER
};

/**
 * @struct Type
 * @brief Represents a type in the type system.
 *
 * Contains information about a type, such as its kind, size, alignment,
 * and any subtype information (e.g., the base type of a pointer).
 */
struct Type {
    TypeKind kind;
    size_t size;
    size_t alignment;

    union {
        /**
         * @struct Pointer
         * @brief Data for pointer types.
         * @var Pointer::base The type that the pointer points to.
         */
        struct {
            Type* base;
        } pointer;
    } as;
};

#endif // TYPE_SYSTEM_HPP
