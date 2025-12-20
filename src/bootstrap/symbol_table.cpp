#include "symbol_table.hpp"
#include <cstring> // For strcmp

SymbolTable::SymbolTable(ArenaAllocator& arena) : symbols(arena) {
    // The DynamicArray is already initialized by its constructor.
}

bool SymbolTable::insert(const Symbol& symbol) {
    // Check if the symbol already exists.
    if (lookup(symbol.name) != NULL) {
        return false; // Duplicate symbol
    }

    symbols.append(symbol);
    return true;
}

Symbol* SymbolTable::lookup(const char* name) {
    for (size_t i = 0; i < symbols.length(); ++i) {
        if (strcmp(symbols[i].name, name) == 0) {
            return &symbols[i];
        }
    }
    return NULL; // Symbol not found
}
