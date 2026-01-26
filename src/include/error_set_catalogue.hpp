#ifndef ERROR_SET_CATALOGUE_HPP
#define ERROR_SET_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation

/**
 * @struct ErrorSetInfo
 * @brief Stores information about a detected error set.
 */
struct ErrorSetInfo {
    const char* name;                   // "MyErrors" or NULL for anonymous
    DynamicArray<const char*>* tags;    // List of error tag names (interned strings)
    SourceLocation location;
    bool is_imported;                   // Whether it was detected via @import
};

/**
 * @class ErrorSetCatalogue
 * @brief Catalogues all error sets found during parsing for documentation and analysis.
 */
class ErrorSetCatalogue {
public:
    ErrorSetCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds a new error set to the catalogue.
     * @param name The name of the error set (can be NULL).
     * @param tags A dynamic array of tag names (interned strings).
     * @param loc The source location where the error set was defined.
     * @param is_imported True if the error set comes from an @import statement.
     */
    void addErrorSet(const char* name, DynamicArray<const char*>* tags, SourceLocation loc, bool is_imported = false);

    /**
     * @brief Updates the name of the most recently added error set, if it doesn't already have one.
     * @param name The name to assign.
     */
    void updateLastSetName(const char* name);

    /**
     * @brief Prints a summary of all catalogued error sets to debug output.
     */
    void printSummary() const;

    /**
     * @brief Returns the number of catalogued error sets.
     */
    int count() const;

    /**
     * @brief Returns the list of catalogued error sets.
     */
    const DynamicArray<ErrorSetInfo>* getErrorSets() const { return error_sets_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<ErrorSetInfo>* error_sets_;
};

#endif // ERROR_SET_CATALOGUE_HPP
