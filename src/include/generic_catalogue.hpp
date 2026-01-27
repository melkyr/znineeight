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

/**
 * @class GenericCatalogue
 * @brief Catalogues all generic function instantiations detected during semantic analysis.
 */
class GenericCatalogue {
public:
    GenericCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds a new generic instantiation to the catalogue.
     */
    void addInstantiation(const char* name, Type** types, int count, SourceLocation loc);

    /**
     * @brief Returns the number of catalogued instantiations.
     */
    int count() const;

    /**
     * @brief Returns the list of catalogued instantiations.
     */
    const DynamicArray<GenericInstantiation>* getInstantiations() const { return instantiations_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<GenericInstantiation>* instantiations_;
};

#endif // GENERIC_CATALOGUE_HPP
