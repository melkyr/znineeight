#ifndef SYMBOL_TABLE_HPP
#define SYMBOL_TABLE_HPP

#include "common.hpp"
#include "type_system.hpp"
#include "memory.hpp"

// Forward-declare ASTNode to avoid circular dependency
struct ASTNode;

/**
 * @enum SymbolKind
 * @brief Distinguishes the different kinds of symbols that can be stored.
 */
enum SymbolKind {
    SYMBOL_VARIABLE,
    SYMBOL_FUNCTION,
    SYMBOL_TYPE
};

/**
 * @struct Symbol
 * @brief Represents a named entity in the source code, such as a variable,
 *        function, or type.
 */
struct Symbol {
    SymbolKind kind;
    const char* name;
    Type* type;
    size_t address_offset; // For variables
    ASTNode* definition;   // Pointer to the AST declaration node
};

/**
 * @class SymbolTable
 * @brief Manages symbols and their scopes.
 *
 * For the initial bootstrap phase, this is a simple, single-scope table.
 */
class SymbolTable {
public:
    /**
     * @brief Constructs a new SymbolTable.
     * @param arena The ArenaAllocator to use for symbol storage.
     */
    SymbolTable(ArenaAllocator& arena);

    /**
     * @brief Inserts a new symbol into the table.
     * @param symbol The symbol to insert.
     * @return True on success, false if the symbol already exists.
     */
    bool insert(const Symbol& symbol);

    /**
     * @brief Looks up a symbol by name.
     * @param name The name of the symbol to find.
     * @return A pointer to the Symbol if found, otherwise NULL.
     */
    Symbol* lookup(const char* name);

private:
    DynamicArray<Symbol> symbols;
};

#endif // SYMBOL_TABLE_HPP
