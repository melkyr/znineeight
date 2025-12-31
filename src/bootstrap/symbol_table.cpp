#include "symbol_table.hpp"
#include <string.h>
#include <new>
#include "memory.hpp"
#include "hash.hpp"

// --- SymbolBuilder Implementation ---

SymbolBuilder::SymbolBuilder(ArenaAllocator& arena) : arena_(arena) {
    // Zero-initialize the temporary symbol to ensure all fields are set.
    temp_symbol_.name = NULL;
    temp_symbol_.symbol_type = NULL;
    temp_symbol_.details = NULL;
    temp_symbol_.scope_level = 0;
    temp_symbol_.flags = 0;
}

SymbolBuilder& SymbolBuilder::withName(const char* name) {
    temp_symbol_.name = name;
    return *this;
}

SymbolBuilder& SymbolBuilder::ofType(SymbolType kind) {
    temp_symbol_.kind = kind;
    return *this;
}

SymbolBuilder& SymbolBuilder::withType(Type* symbol_type) {
    temp_symbol_.symbol_type = symbol_type;
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

// --- Scope Implementation ---

const size_t INITIAL_CAPACITY = 16;
const float MAX_LOAD_FACTOR = 0.75f;

Scope::Scope(ArenaAllocator& allocator)
    : arena(allocator), buckets(allocator), count(0), capacity(INITIAL_CAPACITY)
{
    buckets.resize(capacity);
    for (size_t i = 0; i < capacity; ++i) {
        buckets[i] = NULL;
    }
}

bool Scope::insert(Symbol* symbol) {
    if (find(symbol->name)) {
        return false; // Redeclaration
    }

    if ((float)(count + 1) / capacity > MAX_LOAD_FACTOR) {
        grow();
    }

    u32 hash = hash_string(symbol->name);
    size_t index = hash % capacity;

    // Allocate a new entry from the arena
    SymbolEntry* new_entry = (SymbolEntry*)arena.alloc(sizeof(SymbolEntry));
    new_entry->symbol = symbol;

    // Insert at the head of the bucket's linked list
    new_entry->next = buckets[index];
    buckets[index] = new_entry;
    count++;
    return true;
}

void Scope::grow() {
    size_t new_capacity = capacity * 2;
    DynamicArray<SymbolEntry*> new_buckets(arena);
    new_buckets.resize(new_capacity);
    for (size_t i = 0; i < new_capacity; ++i) {
        new_buckets[i] = NULL;
    }

    for (size_t i = 0; i < capacity; ++i) {
        SymbolEntry* entry = buckets[i];
        while (entry) {
            SymbolEntry* next = entry->next;
            u32 hash = hash_string(entry->symbol->name);
            size_t new_index = hash % new_capacity;
            entry->next = new_buckets[new_index];
            new_buckets[new_index] = entry;
            entry = next;
        }
    }

    buckets = new_buckets;
    capacity = new_capacity;
}
Symbol* Scope::find(const char* name) {
    u32 hash = hash_string(name);
    size_t index = hash % capacity;

    for (SymbolEntry* entry = buckets[index]; entry != NULL; entry = entry->next) {
        if (strcmp(entry->symbol->name, name) == 0) {
            return entry->symbol;
        }
    }
    return NULL;
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
    // Allocate a copy of the symbol in the arena
    Symbol* new_symbol = (Symbol*)arena_.alloc(sizeof(Symbol));
    *new_symbol = symbol;

    // Add the symbol to the current scope's hash table.
    // The scope's insert method will handle the duplicate check.
    return scopes.back()->insert(new_symbol);
}

Symbol* SymbolTable::lookup(const char* name) {
    // Search from the innermost scope to the outermost.
    for (int i = scopes.length() - 1; i >= 0; --i) {
        Symbol* symbol = scopes[i]->find(name);
        if (symbol) {
            return symbol;
        }
    }
    return NULL; // Not found in any scope.
}

Symbol* SymbolTable::lookupInCurrentScope(const char* name) {
    if (scopes.length() == 0) {
        return NULL;
    }
    return scopes.back()->find(name);
}

unsigned int SymbolTable::getCurrentScopeLevel() const {
    return current_scope_level_;
}
