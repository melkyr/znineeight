#ifndef ERRDEFER_CATALOGUE_HPP
#define ERRDEFER_CATALOGUE_HPP

#include "common.hpp"
#include "memory.hpp"
#include "lexer.hpp" // For SourceLocation

/**
 * @struct ErrDeferInfo
 * @brief Stores metadata about a detected 'errdefer' statement.
 */
struct ErrDeferInfo {
    SourceLocation location;
};

/**
 * @class ErrDeferCatalogue
 * @brief Catalogues all 'errdefer' statements found during validation.
 */
class ErrDeferCatalogue {
public:
    ErrDeferCatalogue(ArenaAllocator& arena);

    /**
     * @brief Adds a new 'errdefer' statement to the catalogue.
     */
    void addErrDefer(SourceLocation loc);

    /**
     * @brief Returns the number of catalogued 'errdefer' statements.
     */
    int count() const;

    /**
     * @brief Returns the list of catalogued 'errdefer' statements.
     */
    const DynamicArray<ErrDeferInfo>* getErrDefers() const { return err_defers_; }

private:
    ArenaAllocator& arena_;
    DynamicArray<ErrDeferInfo>* err_defers_;
};

#endif // ERRDEFER_CATALOGUE_HPP
