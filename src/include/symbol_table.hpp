#ifndef SYMBOL_TABLE_HPP
#define SYMBOL_TABLE_HPP

#include "common.hpp"
#include "ast.hpp"
#include "memory.hpp"
#include "source_manager.hpp"

// Forward declaration
class ArenaAllocator;

enum SymbolType {
    SYMBOL_VARIABLE,
    SYMBOL_FUNCTION,
    SYMBOL_TYPE,
    SYMBOL_UNION_TYPE,
};

struct Symbol {
    const char* name;
    SymbolType type;
    SourceLocation location;
    void* details;
    unsigned int scope_level;
    unsigned int flags;
};

class SymbolBuilder {
    ArenaAllocator& arena_;
    Symbol temp_symbol_;

public:
    SymbolBuilder(ArenaAllocator& arena);
    SymbolBuilder& withName(const char* name);
    SymbolBuilder& ofType(SymbolType type);
    SymbolBuilder& atLocation(const SourceLocation& loc);
    SymbolBuilder& definedBy(void* details);
    SymbolBuilder& inScope(unsigned int level);
    SymbolBuilder& withFlags(unsigned int flags);
    Symbol build();
};

struct Scope {
    DynamicArray<Symbol> symbols;
    Scope(ArenaAllocator& arena) : symbols(arena) {}
};

class SymbolTable {
    ArenaAllocator& arena_;
    DynamicArray<Scope*> scopes;
    unsigned int current_scope_level_;

public:
    SymbolTable(ArenaAllocator& arena);
    void enterScope();
    void exitScope();
    bool insert(const Symbol& symbol);
    Symbol* lookup(const char* name);
    Symbol* lookupInCurrentScope(const char* name);
    unsigned int getCurrentScopeLevel() const;
};

#endif // SYMBOL_TABLE_HPP
