#ifndef SYMBOL_TABLE_HPP
#define SYMBOL_TABLE_HPP

#include "common.hpp"
#include "type_system.hpp"
#include "ast.hpp"
#include "memory.hpp"

struct Symbol {
    enum Kind { VARIABLE, FUNCTION, TYPE } kind;
    const char* name;
    Type* type;
    u32 address_offset;
    ASTNode* definition;
};

class SymbolTable {
    DynamicArray<Symbol>* symbols;
    ArenaAllocator* arena;

public:
    SymbolTable(ArenaAllocator* allocator);
    Symbol* lookup(const char* name);
    void insert(Symbol& sym);
};

#endif // SYMBOL_TABLE_HPP
