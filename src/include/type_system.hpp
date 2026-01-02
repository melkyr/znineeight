#ifndef TYPE_SYSTEM_HPP
#define TYPE_SYSTEM_HPP

#include <cstddef> // For size_t
#include "memory.hpp" // For DynamicArray

// Forward-declare Type for the pointer union member
struct Type;

/**
 * @enum TypeKind
 * @brief Defines the kind of each type in the bootstrap type system.
 */
enum TypeKind {
    TYPE_VOID,
    TYPE_BOOL,
    // Integer Types
    TYPE_I8, TYPE_I16, TYPE_I32, TYPE_I64,
    TYPE_U8, TYPE_U16, TYPE_U32, TYPE_U64,
    // Platform-dependent Integer Types
    TYPE_ISIZE, // Maps to i32 on 32-bit target
    TYPE_USIZE, // Maps to u32 on 32-bit target
    // Floating-Point Types
    TYPE_F32,
    TYPE_F64,
    // Complex Types
    TYPE_POINTER,
    TYPE_FUNCTION
};

/**
 * @struct Type
 * @brief Represents a type within the bootstrap compiler's type system.
 */
struct Type {
    TypeKind kind;
    size_t size;
    size_t alignment;

    union {
        struct {
            Type* base;
            bool is_const;
        } pointer;
        struct {
            DynamicArray<Type*>* params;
            Type* return_type;
        } function;
    } as;
};

/**
 * @brief Resolves a string identifier into a pointer to a primitive Type.
 * @param name The string name of the type (e.g., "i32", "bool").
 * @return A pointer to the static Type object, or NULL if the name is not a
 *         known primitive type.
 */
Type* resolvePrimitiveTypeName(const char* name);

// Forward declaration for ArenaAllocator
class ArenaAllocator;

/**
 * @brief Creates a new pointer Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param base_type A pointer to the Type that the new pointer type should point to.
 * @param is_const True if the pointer type is const-qualified.
 * @return A pointer to the newly allocated Type object.
 */
Type* createPointerType(ArenaAllocator& arena, Type* base_type, bool is_const);

/**
 * @brief Creates a new function Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param params A dynamic array of pointers to the parameter types.
 * @param return_type A pointer to the return type.
 * @return A pointer to the newly allocated Type object.
 */
Type* createFunctionType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type);

/**
 * @brief Converts a Type object to its string representation.
 * @param type A pointer to the Type object.
 * @param buffer The character buffer to write the string into.
 * @param buffer_size The size of the character buffer.
 */
void typeToString(Type* type, char* buffer, size_t buffer_size);

// Global instances of primitive types, defined in type_system.cpp
extern Type g_type_void;
extern Type g_type_bool;
extern Type g_type_i8;
extern Type g_type_i16;
extern Type g_type_i32;
extern Type g_type_i64;
extern Type g_type_u8;
extern Type g_type_u16;
extern Type g_type_u32;
extern Type g_type_u64;
extern Type g_type_isize;
extern Type g_type_usize;
extern Type g_type_f32;
extern Type g_type_f64;

#endif // TYPE_SYSTEM_HPP
