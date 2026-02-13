#ifndef C_VARIABLE_ALLOCATOR_HPP
#define C_VARIABLE_ALLOCATOR_HPP

#include "common.hpp"
#include "memory.hpp"

struct Symbol;

/**
 * @class CVariableAllocator
 * @brief Manages C variable names, ensuring they are unique, C89-compliant,
 *        and avoid keywords.
 *
 * This class is designed to be reset per function body.
 */
class CVariableAllocator {
public:
    /**
     * @brief Constructs a new CVariableAllocator.
     * @param arena The ArenaAllocator to use for temporary strings.
     */
    CVariableAllocator(ArenaAllocator& arena);

    /**
     * @brief Resets the allocator for a new function scope.
     */
    void reset();

    /**
     * @brief Allocates a unique C name for a symbol.
     * @param sym The symbol to allocate a name for.
     * @return A unique, C89-compliant name.
     */
    const char* allocate(Symbol* sym);

    /**
     * @brief Generates a unique C name based on a prefix.
     * @param base The base name for the temporary variable.
     * @return A unique, C89-compliant name.
     */
    const char* generate(const char* base);

private:
    /**
     * @brief Ensures a name is unique, truncated to 31 chars, and not a keyword.
     */
    const char* makeUnique(const char* desired);

    /**
     * @brief Checks if a name has already been assigned in the current scope.
     */
    bool isAssigned(const char* name) const;

    struct SymbolEntry {
        Symbol* sym;
        const char* c_name;
    };

    ArenaAllocator& arena_;
    DynamicArray<const char*> assigned_names_;
    DynamicArray<SymbolEntry> symbol_cache_;

    // Prevent copying
    CVariableAllocator(const CVariableAllocator&);
    CVariableAllocator& operator=(const CVariableAllocator&);
};

#endif // C_VARIABLE_ALLOCATOR_HPP
