#ifndef GENERIC_CATALOGUE_HPP
#define GENERIC_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation

struct Type;

/**
 * @struct GenericInstantiation
 * @brief Stores information about a generic function instantiation.
 */
struct GenericInstantiation {
    const char* function_name;
    Type* type_arguments[4];
    int type_count;
    SourceLocation location;
};

enum GenericParamKind {
    GENERIC_KIND_COMPTIME,
    GENERIC_KIND_ANYTYPE,
    GENERIC_KIND_TYPE_PARAM
};

struct GenericDefinitionInfo {
    const char* function_name;
    SourceLocation location;
    GenericParamKind kind;
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
    void addInstantiation(const char* name, Type** types, int count, SourceLocation loc);

    /**
     * @brief Adds a new generic function definition to the catalogue.
     */
    void addDefinition(const char* name, SourceLocation loc, GenericParamKind kind);

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
