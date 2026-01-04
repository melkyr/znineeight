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
    TYPE_ARRAY,
    TYPE_FUNCTION,
    TYPE_ENUM
};

/**
 * @struct EnumMember
 * @brief Represents a single member of an enum.
 */
struct EnumMember {
    const char* name;
    i64 value;
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
        struct ArrayDetails {
            Type* element_type;
            u64 size;
        } array;
        struct {
            Type* backing_type;
            DynamicArray<EnumMember>* members;
        } enum_details;
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
 * @brief Creates a new array Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param element_type A pointer to the Type of the array elements.
 * @param size The number of elements in the array.
 * @return A pointer to the newly allocated Type object.
 */
Type* createArrayType(ArenaAllocator& arena, Type* element_type, u64 size);

/**
 * @brief Creates a new enum Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param backing_type A pointer to the enum's backing type.
 * @param members A dynamic array of the enum's members.
 * @return A pointer to the newly allocated Type object.
 */
Type* createEnumType(ArenaAllocator& arena, Type* backing_type, DynamicArray<EnumMember>* members);

/**
 * @brief Converts a Type object to its string representation.
 * @param type A pointer to the Type object.
 * @param buffer The character buffer to write the string into.
 * @param buffer_size The size of the character buffer.
 */
void typeToString(Type* type, char* buffer, size_t buffer_size);

// Accessor functions for global primitive types to prevent static init order fiasco.
Type* get_g_type_void();
Type* get_g_type_bool();
Type* get_g_type_i8();
Type* get_g_type_i16();
Type* get_g_type_i32();
Type* get_g_type_i64();
Type* get_g_type_u8();
Type* get_g_type_u16();
Type* get_g_type_u32();
Type* get_g_type_u64();
Type* get_g_type_isize();
Type* get_g_type_usize();
Type* get_g_type_f32();
Type* get_g_type_f64();

#endif // TYPE_SYSTEM_HPP
