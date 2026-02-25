#ifndef TYPE_SYSTEM_HPP
#define TYPE_SYSTEM_HPP

#include <cstddef> // For size_t
#include "memory.hpp" // For DynamicArray
#include "source_manager.hpp" // For SourceLocation

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
    TYPE_NULL,
    TYPE_UNDEFINED,
    TYPE_ARRAY,
    TYPE_SLICE,
    TYPE_INTEGER_LITERAL,
    TYPE_FUNCTION,
    TYPE_FUNCTION_POINTER,
    TYPE_ENUM,
    TYPE_STRUCT,
    TYPE_UNION,
    TYPE_ERROR_UNION,
    TYPE_ERROR_SET,
    TYPE_OPTIONAL,
    TYPE_NORETURN,
    TYPE_TYPE,
    TYPE_ANYTYPE,
    TYPE_MODULE,
    TYPE_TUPLE,
    TYPE_PLACEHOLDER
};

/**
 * @struct StructField
 * @brief Represents a single field within a struct type.
 */
struct StructField {
    const char* name;
    Type* type;
    size_t offset;
    size_t size;
    size_t alignment;
};

/**
 * @struct EnumMember
 * @brief Represents a single member of an enum.
 */
struct EnumMember {
    const char* name;
    i64 value;
    SourceLocation loc;
};

/**
 * @struct Type
 * @brief Represents a type within the bootstrap compiler's type system.
 */
struct Type {
    TypeKind kind;
    size_t size;
    size_t alignment;
    const char* c_name; // Mangled C89 name for structs, unions, enums

    union {
        struct {
            Type* base;
            bool is_const;
            bool is_many;
        } pointer;
        struct {
            DynamicArray<Type*>* params;
            Type* return_type;
        } function;
        struct {
            DynamicArray<Type*>* param_types;
            Type* return_type;
        } function_pointer;
        struct ArrayDetails {
            Type* element_type;
            u64 size;
        } array;
        struct {
            Type* element_type;
            bool is_const;
        } slice;
        struct {
            // This is used for temporary types during type checking
            // and does not represent a concrete storable type.
            i64 value;
        } integer_literal;
        struct {
            const char* name;
            Type* backing_type;
            DynamicArray<EnumMember>* members;
            i64 min_value;
            i64 max_value;
        } enum_details;
        struct {
            const char* name;
            DynamicArray<StructField>* fields;
            bool is_tagged;
            Type* tag_type;
        } struct_details;
        struct {
            Type* payload;
            Type* error_set; // NULL for inferred
            bool is_inferred;
        } error_union;
        struct {
            const char* name; // NULL for anonymous
            DynamicArray<const char*>* tags;
            bool is_anonymous;
        } error_set;
        struct {
            Type* payload;
        } optional;
        struct {
            const char* name;
            struct Module* module_ptr;
        } module;
        struct {
            DynamicArray<Type*>* elements;
        } tuple;
        struct {
            const char* name;
            struct ASTNode* decl_node;
            struct Module* module;
            bool is_resolving;
            DynamicArray<struct Type*>* dependents;
        } placeholder;
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
 * @class TypeInterner
 * @brief Deduplicates complex types to save memory.
 */
class TypeInterner {
public:
    TypeInterner(ArenaAllocator& arena);
    Type* getPointerType(Type* base_type, bool is_const, bool is_many = false);
    Type* getArrayType(Type* element_type, u64 size);
    Type* getSliceType(Type* element_type, bool is_const);
    Type* getOptionalType(Type* payload);
    Type* getErrorUnionType(Type* payload, Type* error_set, bool is_inferred);
    Type* getErrorSetType(const char* name, DynamicArray<const char*>* tags, bool is_anonymous);

    size_t getUniqueCount() const { return unique_count; }
    size_t getDeduplicationCount() const { return dedupe_count; }

private:
    ArenaAllocator& arena_;
    struct Entry {
        Type* type;
        Entry* next;
    };
    Entry* buckets[256];
    size_t unique_count;
    size_t dedupe_count;

    u32 hashType(TypeKind kind, void* p1, u64 v1);
};

/**
 * @brief Creates a new pointer Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param base_type A pointer to the Type that the new pointer type should point to.
 * @param is_const True if the pointer type is const-qualified.
 * @return A pointer to the newly allocated Type object.
 */
Type* createPointerType(ArenaAllocator& arena, Type* base_type, bool is_const, bool is_many = false, TypeInterner* interner = NULL);

/**
 * @brief Creates a new function Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param params A dynamic array of pointers to the parameter types.
 * @param return_type A pointer to the return type.
 * @return A pointer to the newly allocated Type object.
 */
Type* createFunctionType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type);

/**
 * @brief Creates a new function pointer Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param params A dynamic array of pointers to the parameter types.
 * @param return_type A pointer to the return type.
 * @return A pointer to the newly allocated Type object.
 */
Type* createFunctionPointerType(ArenaAllocator& arena, DynamicArray<Type*>* params, Type* return_type);

/**
 * @brief Creates a new array Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param element_type A pointer to the Type of the array elements.
 * @param size The number of elements in the array.
 * @return A pointer to the newly allocated Type object.
 */
Type* createArrayType(ArenaAllocator& arena, Type* element_type, u64 size, TypeInterner* interner = NULL);

/**
 * @brief Creates a new slice Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param element_type A pointer to the Type of the slice elements.
 * @param is_const True if the slice elements are const.
 * @return A pointer to the newly allocated Type object.
 */
Type* createSliceType(ArenaAllocator& arena, Type* element_type, bool is_const = false, TypeInterner* interner = NULL);

/**
 * @brief Creates a new struct Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param fields A dynamic array of the struct's fields.
 * @param name The optional name of the struct type.
 * @return A pointer to the newly allocated Type object.
 */
Type* createStructType(ArenaAllocator& arena, DynamicArray<StructField>* fields, const char* name = NULL);

/**
 * @brief Creates a new union Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param fields A dynamic array of the union's fields.
 * @param name The optional name of the union type.
 * @param is_tagged True if it's a tagged union.
 * @param tag_type The tag enum type for a tagged union.
 * @return A pointer to the newly allocated Type object.
 */
Type* createUnionType(ArenaAllocator& arena, DynamicArray<StructField>* fields, const char* name = NULL, bool is_tagged = false, Type* tag_type = NULL);

/**
 * @brief Creates a new error union Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param payload The payload type.
 * @param error_set The error set type (can be NULL for inferred).
 * @param is_inferred True if the error set is inferred (!T).
 * @return A pointer to the newly allocated Type object.
 */
Type* createErrorUnionType(ArenaAllocator& arena, Type* payload, Type* error_set, bool is_inferred, TypeInterner* interner = NULL);

/**
 * @brief Creates a new optional Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param payload The payload type.
 * @return A pointer to the newly allocated Type object.
 */
Type* createOptionalType(ArenaAllocator& arena, Type* payload, TypeInterner* interner = NULL);

/**
 * @brief Creates a new error set Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param name The name of the error set (can be NULL).
 * @param tags A dynamic array of tag names (interned strings).
 * @param is_anonymous True if the error set is anonymous.
 * @return A pointer to the newly allocated Type object.
 */
Type* createErrorSetType(ArenaAllocator& arena, const char* name, DynamicArray<const char*>* tags, bool is_anonymous, TypeInterner* interner = NULL);

/**
 * @brief Calculates the layout (offsets, total size, alignment) of a struct type.
 * @param struct_type The struct type to calculate the layout for.
 */
void calculateStructLayout(Type* struct_type);

/**
 * @brief Refreshes the layout of a type (recalculates size and alignment).
 *        Useful when a placeholder base type has been resolved.
 */
void refreshTypeLayout(Type* type);

/**
 * @brief Registers a dependent type that should be updated when the given base type is resolved.
 */
void addDependentRecursively(Type* base, Type* dependent);

/**
 * @brief Creates a new enum Type object from the arena.
 * @param arena The ArenaAllocator to use for allocation.
 * @param name The name of the enum type (can be NULL for anonymous).
 * @param backing_type A pointer to the enum's backing type.
 * @param members A dynamic array of the enum's members.
 * @param min_val The minimum value in the enum.
 * @param max_val The maximum value in the enum.
 * @return A pointer to the newly allocated Type object.
 */
Type* createEnumType(ArenaAllocator& arena, const char* name, Type* backing_type, DynamicArray<EnumMember>* members, i64 min_val, i64 max_val);

/**
 * @brief Creates a new module Type object.
 */
Type* createModuleType(ArenaAllocator& arena, const char* name);

/**
 * @brief Creates a new tuple Type object.
 */
Type* createTupleType(ArenaAllocator& arena, DynamicArray<Type*>* elements);

/**
 * @brief Converts a Type object to its string representation.
 * @param type A pointer to the Type object.
 * @param buffer The character buffer to write the string into.
 * @param buffer_size The size of the character buffer.
 */
void typeToString(Type* type, char* buffer, size_t buffer_size);

/**
 * @brief Checks if two types are structurally equal.
 * @param a The first type.
 * @param b The second type.
 * @return True if the types are equal, false otherwise.
 */
bool areTypesEqual(Type* a, Type* b);

/**
 * @brief Checks if two function signatures are structurally equal.
 * @param a_params The parameters of the first function.
 * @param a_return The return type of the first function.
 * @param b_params The parameters of the second function.
 * @param b_return The return type of the second function.
 * @return True if the signatures match, false otherwise.
 */
bool signaturesMatch(DynamicArray<Type*>* a_params, Type* a_return, DynamicArray<Type*>* b_params, Type* b_return);

    /**
     * @brief Checks if a type is complete (has a known size and alignment).
     * @param type The type to check.
     * @return True if the type is complete, false otherwise.
     */
    bool isTypeComplete(Type* type);

    /**
     * @brief Recursively checks if a type contains a placeholder.
     */
    bool containsPlaceholder(Type* type);

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
Type* get_g_type_null();
Type* get_g_type_undefined();
Type* get_g_type_type();
Type* get_g_type_noreturn();
Type* get_g_type_anytype();

#endif // TYPE_SYSTEM_HPP
