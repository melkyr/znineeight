#ifndef CATCH_EXPRESSION_CATALOGUE_HPP
#define CATCH_EXPRESSION_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation
#include "type_system.hpp"
#include "try_expression_catalogue.hpp" // For ExtractionStrategy

/**
 * @struct CatchExpressionInfo
 * @brief Stores metadata about a detected 'catch' expression for analysis and documentation.
 */
struct CatchExpressionInfo {
    SourceLocation location;          // Where the `catch` keyword is
    const char* context_type;         // "variable_decl", "assignment", etc.
    Type* error_type;                // Type of error being caught (error union)
    Type* handler_type;              // Type of the catch handler expression
    Type* result_type;               // Result type after catch
    bool is_chained;                 // Part of a catch chain (a catch b catch c)
    int chain_index;                 // Position in chain (0 = first)
    const char* error_param_name;    // |err| parameter name or NULL if none

    // Extraction Analysis fields
    ExtractionStrategy extraction_strategy;
    bool stack_safe;
};

/**
 * @class CatchExpressionCatalogue
 * @brief Catalogues all 'catch' expressions found during validation.
 */
class CatchExpressionCatalogue {
public:
    CatchExpressionCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds a new 'catch' expression to the catalogue.
     * @return A pointer to the newly added entry.
     */
    CatchExpressionInfo* addCatchExpression(SourceLocation loc, const char* context_type,
                                           Type* error_type, Type* handler_type, Type* result_type,
                                           const char* error_param_name, int chain_index, bool is_chained);

    /**
     * @brief Returns the number of catalogued 'catch' expressions.
     */
    int count() const;

    /**
     * @brief Returns the list of catalogued 'catch' expressions.
     */
    const DynamicArray<CatchExpressionInfo>* getCatchExpressions() const { return catch_expressions_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<CatchExpressionInfo>* catch_expressions_;
};

#endif // CATCH_EXPRESSION_CATALOGUE_HPP
