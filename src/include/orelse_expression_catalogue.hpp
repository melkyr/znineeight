#ifndef ORELSE_EXPRESSION_CATALOGUE_HPP
#define ORELSE_EXPRESSION_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation
#include "type_system.hpp"

/**
 * @struct OrelseExpressionInfo
 * @brief Stores metadata about a detected 'orelse' expression for analysis and documentation.
 */
struct OrelseExpressionInfo {
    SourceLocation location;
    const char* context_type;
    Type* left_type;      // Optional type (like ?T)
    Type* right_type;     // Default value type
    Type* result_type;    // Result after orelse
};

/**
 * @class OrelseExpressionCatalogue
 * @brief Catalogues all 'orelse' expressions found during validation.
 */
class OrelseExpressionCatalogue {
public:
    OrelseExpressionCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds a new 'orelse' expression to the catalogue.
     */
    void addOrelseExpression(SourceLocation loc, const char* context_type,
                            Type* left_type, Type* right_type, Type* result_type);

    /**
     * @brief Returns the number of catalogued 'orelse' expressions.
     */
    int count() const;

    /**
     * @brief Returns the list of catalogued 'orelse' expressions.
     */
    const DynamicArray<OrelseExpressionInfo>* getOrelseExpressions() const { return orelse_expressions_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<OrelseExpressionInfo>* orelse_expressions_;
};

#endif // ORELSE_EXPRESSION_CATALOGUE_HPP
