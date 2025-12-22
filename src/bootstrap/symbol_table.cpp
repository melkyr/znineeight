#include "symbol_table.hpp"
#include <string.h>
#include <new>

SymbolTable::SymbolTable(ArenaAllocator* allocator)
{
    arena = allocator;
    symbols = (DynamicArray<Symbol>*)arena->alloc(sizeof(DynamicArray<Symbol>));
    new (symbols) DynamicArray<Symbol>(*arena);
}

Symbol* SymbolTable::lookup(const char* name)
{
    for (size_t i = 0; i < symbols->length(); ++i) {
        if (strcmp((*symbols)[i].name, name) == 0) {
            return &(*symbols)[i];
        }
    }
    return NULL;
}

void SymbolTable::insert(Symbol& sym)
{
    symbols->append(sym);
}
