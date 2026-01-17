#include "symbol_table.hpp"
#include <string.h>
#include <new>
#include "memory.hpp"

// 32-bit FNV-1a hash function
static u32 hash_string(const char* str) {
    u32 hash = 2166136261u; // FNV_offset_basis
    for (const char* p = str; *p; p++) {
        hash ^= (u8)*p;
        hash *= 16777619u; // FNV_prime
    }
    return hash;
}

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

Scope::Scope(ArenaAllocator& arena, size_t initial_bucket_count)
    : buckets(arena), symbol_count(0), bucket_count(initial_bucket_count), arena(arena)
{
    for (size_t i = 0; i < bucket_count; ++i) {
        buckets.append(NULL);
    }
}

void Scope::insert(Symbol& symbol) {
    // Resize if load factor exceeds 0.75
    if (symbol_count + 1 > bucket_count * 0.75) {
        resize();
    }

    u32 hash = hash_string(symbol.name);
    size_t index = hash % bucket_count;

    // Allocate a new entry from the arena
    SymbolEntry* new_entry = (SymbolEntry*)arena.alloc(sizeof(SymbolEntry));
    new_entry->symbol = symbol;

    // Insert at the head of the bucket's linked list
    new_entry->next = buckets[index];
    buckets[index] = new_entry;
    symbol_count++;
}

Symbol* Scope::find(const char* name) {
    u32 hash = hash_string(name);
    size_t index = hash % bucket_count;

    for (SymbolEntry* entry = buckets[index]; entry != NULL; entry = entry->next) {
        if (strcmp(entry->symbol.name, name) == 0) {
            return &entry->symbol;
        }
    }
    return NULL;
}

void Scope::resize() {
    size_t new_bucket_count = bucket_count * 2;
    DynamicArray<SymbolEntry*> new_buckets(arena);
    for (size_t i = 0; i < new_bucket_count; ++i) {
        new_buckets.append(NULL);
    }

    // Re-hash and insert all existing symbols into the new buckets
    for (size_t i = 0; i < bucket_count; ++i) {
        SymbolEntry* entry = buckets[i];
        while (entry != NULL) {
            SymbolEntry* next = entry->next; // Save next entry

            u32 hash = hash_string(entry->symbol.name);
            size_t new_index = hash % new_bucket_count;

            // Insert into the new bucket
            entry->next = new_buckets[new_index];
            new_buckets[new_index] = entry;

            entry = next;
        }
    }

    // Replace old buckets with the new ones
    buckets = new_buckets;
    bucket_count = new_bucket_count;
}


// --- SymbolTable Implementation ---

SymbolTable::SymbolTable(ArenaAllocator& arena)
    : arena_(arena), scopes(arena), all_scopes_(arena), current_scope_level_(0)
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
    all_scopes_.append(new_scope);
}

void SymbolTable::exitScope() {
    if (scopes.length() > 1) { // Do not exit the global scope.
        scopes.pop_back();
        current_scope_level_--;
    }
}

bool SymbolTable::insert(Symbol& symbol) {
    // Check for redeclaration in the current scope.
    if (lookupInCurrentScope(symbol.name)) {
        return false; // Symbol already exists.
    }
    // Assign the current scope level to the symbol.
    symbol.scope_level = getCurrentScopeLevel();
    // Add the symbol to the current scope.
    scopes.back()->insert(symbol);
    return true;
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

Symbol* SymbolTable::findInAnyScope(const char* name) {
    // Search all scopes ever created, from most recent to oldest.
    for (int i = (int)all_scopes_.length() - 1; i >= 0; --i) {
        Symbol* symbol = all_scopes_[i]->find(name);
        if (symbol) {
            return symbol;
        }
    }
    return NULL;
}

unsigned int SymbolTable::getCurrentScopeLevel() const {
    return current_scope_level_;
}
