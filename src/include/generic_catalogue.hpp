#ifndef GENERIC_CATALOGUE_HPP
#define GENERIC_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation

struct Type;

enum GenericParamKind {
    GENERIC_PARAM_TYPE,          // e.g., `i32`
    GENERIC_PARAM_COMPTIME_INT,  // e.g., `comptime n: i32 = 10`
    GENERIC_PARAM_COMPTIME_FLOAT, // e.g., `comptime pi: f32 = 3.14`
    GENERIC_PARAM_ANYTYPE        // `anytype`
};

struct GenericParamInfo {
    GenericParamKind kind;
    union {
        Type* type_value;
        i64 int_value;
        double float_value;
    };
    const char* param_name;  // Interned string
};

/**
 * @struct GenericInstantiation
 * @brief Stores information about a generic function instantiation.
 */
struct GenericInstantiation {
    const char* function_name;
    GenericParamInfo params[4];
    int param_count;
    SourceLocation location;
    const char* module;  // NULL or logical name
    bool is_explicit;    // explicit vs implicit
    int specialization_id; // Unique per combination
    u32 param_hash;      // Quick comparison
};

enum GenericDefinitionKind {
    GENERIC_KIND_COMPTIME,
    GENERIC_KIND_ANYTYPE,
    GENERIC_KIND_TYPE_PARAM
};

struct GenericDefinitionInfo {
    const char* function_name;
    SourceLocation location;
    GenericDefinitionKind kind;
};

/**
 * @class GenericCatalogue
 * @brief Catalogues all generic function instantiations and definitions detected.
 */
class GenericCatalogue {
public:
    GenericCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds a new generic instantiation to the catalogue.
     */
    void addInstantiation(const char* name, GenericParamInfo* params, int count, SourceLocation loc, const char* module, bool is_explicit, u32 param_hash);

    /**
     * @brief Adds a new generic function definition to the catalogue.
     */
    void addDefinition(const char* name, SourceLocation loc, GenericDefinitionKind kind);

    /**
     * @brief Merges instantiations and definitions from another catalogue.
     */
    void mergeFrom(const GenericCatalogue& other, const char* module_prefix = "");

    /**
     * @brief Checks if a function is catalogued as generic.
     */
    bool isFunctionGeneric(const char* name) const;

    /**
     * @brief Returns the number of catalogued instantiations.
     */
    int count() const;

    /**
     * @brief Returns the list of catalogued instantiations.
     */
    const DynamicArray<GenericInstantiation>* getInstantiations() const { return instantiations_; }

    /**
     * @brief Returns the list of catalogued definitions.
     */
    const DynamicArray<GenericDefinitionInfo>* getDefinitions() const { return definitions_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<GenericInstantiation>* instantiations_;
    DynamicArray<GenericDefinitionInfo>* definitions_;
};

#endif // GENERIC_CATALOGUE_HPP
