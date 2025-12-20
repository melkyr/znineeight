#include "symbol_table.hpp"
#include <cstring> // For strcmp

SymbolTable::SymbolTable(ArenaAllocator& arena, SymbolTable* parent)
    : symbols(arena), parent(parent) {
    // The DynamicArray is already initialized by its constructor.
}

bool SymbolTable::insert(const Symbol& symbol) {
    // Check if the symbol already exists in the current scope.
    if (lookup_local(symbol.name) != NULL) {
        return false; // Duplicate symbol in the same scope
    }

    symbols.append(symbol);
    return true;
}

Symbol* SymbolTable::lookup(const char* name) {
    Symbol* symbol = lookup_local(name);
    if (symbol != NULL) {
        return symbol;
    }

    if (parent != NULL) {
        return parent->lookup(name);
    }

    return NULL; // Symbol not found in this scope or any parent scope
}

Symbol* SymbolTable::lookup_local(const char* name) {
    for (size_t i = 0; i < symbols.length(); ++i) {
        if (strcmp(symbols[i].name, name) == 0) {
            return &symbols[i];
        }
    }
    return NULL; // Symbol not found
}
