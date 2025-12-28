#include "symbol_table.hpp"
#include <string.h>
#include <new>
#include "memory.hpp"

// --- SymbolBuilder Implementation ---

SymbolBuilder::SymbolBuilder(ArenaAllocator& arena) : arena_(arena) {
    // Zero-initialize the temporary symbol to ensure all fields are set.
    temp_symbol_.name = NULL;
    temp_symbol_.details = NULL;
    temp_symbol_.scope_level = 0;
    temp_symbol_.flags = 0;
}

SymbolBuilder& SymbolBuilder::withName(const char* name) {
    temp_symbol_.name = name;
    return *this;
}

SymbolBuilder& SymbolBuilder::ofType(SymbolType type) {
    temp_symbol_.type = type;
    return *this;
}

SymbolBuilder& SymbolBuilder::atLocation(const SourceLocation& loc) {
    temp_symbol_.location = loc;
    return *this;
}

SymbolBuilder& SymbolBuilder::definedBy(void* details) {
    temp_symbol_.details = details;
    return *this;
}

SymbolBuilder& SymbolBuilder::inScope(unsigned int level) {
    temp_symbol_.scope_level = level;
    return *this;
}

SymbolBuilder& SymbolBuilder::withFlags(unsigned int flags) {
    temp_symbol_.flags = flags;
    return *this;
}

Symbol SymbolBuilder::build() {
    return temp_symbol_;
}


// --- SymbolTable Implementation ---

SymbolTable::SymbolTable(ArenaAllocator& arena)
    : arena_(arena), scopes(arena), current_scope_level_(0)
{
    // The global scope is entered by default upon initialization.
    enterScope();
}

void SymbolTable::enterScope() {
    current_scope_level_++;
    // Allocate and construct a new Scope object from the arena.
    Scope* new_scope = (Scope*)arena_.alloc(sizeof(Scope));
    new (new_scope) Scope(arena_);
    scopes.append(new_scope);
}

void SymbolTable::exitScope() {
    if (scopes.length() > 1) { // Do not exit the global scope.
        scopes.pop_back();
        current_scope_level_--;
    }
}

bool SymbolTable::insert(const Symbol& symbol) {
    // Check for redeclaration in the current scope.
    if (lookupInCurrentScope(symbol.name)) {
        return false; // Symbol already exists.
    }
    // Add the symbol to the current scope.
    scopes.back()->symbols.append(symbol);
    return true;
}

Symbol* SymbolTable::lookup(const char* name) {
    // Search from the innermost scope to the outermost.
    for (int i = scopes.length() - 1; i >= 0; --i) {
        DynamicArray<Symbol>& symbols = scopes[i]->symbols;
        for (size_t j = 0; j < symbols.length(); ++j) {
            if (strcmp(symbols[j].name, name) == 0) {
                return &symbols[j];
            }
        }
    }
    return NULL; // Not found in any scope.
}

Symbol* SymbolTable::lookupInCurrentScope(const char* name) {
    if (scopes.length() == 0) {
        return NULL;
    }
    DynamicArray<Symbol>& current_symbols = scopes.back()->symbols;
    for (size_t i = 0; i < current_symbols.length(); ++i) {
        if (strcmp(current_symbols[i].name, name) == 0) {
            return &current_symbols[i];
        }
    }
    return NULL;
}

unsigned int SymbolTable::getCurrentScopeLevel() const {
    return current_scope_level_;
}
