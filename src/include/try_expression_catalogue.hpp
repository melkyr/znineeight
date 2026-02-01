#ifndef TRY_EXPRESSION_CATALOGUE_HPP
#define TRY_EXPRESSION_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation
#include "type_system.hpp"

/**
 * @enum ExtractionStrategy
 * @brief Strategy for extracting success values from error unions.
 */
enum ExtractionStrategy {
    EXTRACTION_STACK,
    EXTRACTION_ARENA,
    EXTRACTION_OUT_PARAM
};

/**
 * @struct TryExpressionInfo
 * @brief Stores metadata about a detected 'try' expression for analysis and documentation.
 */
struct TryExpressionInfo {
    SourceLocation location;         // Where the `try` keyword is
    const char* context_type;        // "assignment", "return", "call_argument", "variable_decl", etc.
    Type* inner_type;               // Type of the expression being tried (error union)
    Type* result_type;              // Type after unwrapping (payload type)
    bool is_nested;                 // Is this try inside another try?
    int depth;                      // Nesting depth (0 = top-level)

    // Extraction Analysis fields
    ExtractionStrategy extraction_strategy;
    bool stack_safe;
};

/**
 * @class TryExpressionCatalogue
 * @brief Catalogues all 'try' expressions found during validation.
 */
class TryExpressionCatalogue {
public:
    TryExpressionCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds a new 'try' expression to the catalogue.
     * @return The index of the newly added entry.
     */
    int addTryExpression(SourceLocation loc, const char* context_type,
                        Type* inner_type, Type* result_type, int depth);

    /**
     * @brief Returns a reference to a catalogued 'try' expression by index.
     */
    TryExpressionInfo& getTryExpression(int index) { return (*try_expressions_)[index]; }

    /**
     * @brief Returns the number of catalogued 'try' expressions.
     */
    int count() const;

    /**
     * @brief Returns the list of catalogued 'try' expressions.
     */
    const DynamicArray<TryExpressionInfo>* getTryExpressions() const { return try_expressions_; }

    /**
     * @brief Prints a summary of detected 'try' expressions (for debugging).
     */
    void printSummary() const;

private:
    ArenaAllocator& arena_;
    DynamicArray<TryExpressionInfo>* try_expressions_;
};

#endif // TRY_EXPRESSION_CATALOGUE_HPP
