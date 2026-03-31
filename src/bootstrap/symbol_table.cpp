#include "symbol_table.hpp"
#include "platform.hpp"
#include <new>
#include "memory.hpp"

#ifdef DEBUG_VISIBILITY
    #define DEBUG_SYMBOL 1
#endif

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
    temp_symbol_.module_name = NULL;
    temp_symbol_.mangled_name = NULL;
    temp_symbol_.symbol_type = NULL;
    temp_symbol_.details = NULL;
    temp_symbol_.scope_level = 0;
    temp_symbol_.flags = 0;
    temp_symbol_.is_generic = false;
    temp_symbol_.c_prototype_type = NULL;
    // location is a struct, hopefully its default constructor (if any) or bitwise zero is fine
}

SymbolBuilder& SymbolBuilder::withName(const char* name) {
    temp_symbol_.name = name;
    return *this;
}

SymbolBuilder& SymbolBuilder::withModule(const char* module_name) {
    temp_symbol_.module_name = module_name;
    return *this;
}

SymbolBuilder& SymbolBuilder::withMangledName(const char* mangled_name) {
    temp_symbol_.mangled_name = mangled_name;
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

SymbolBuilder& SymbolBuilder::asGeneric(bool generic) {
    temp_symbol_.is_generic = generic;
    return *this;
}

SymbolBuilder& SymbolBuilder::withCPrototypeType(Type* type) {
    temp_symbol_.c_prototype_type = type;
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
#ifdef DEBUG_VISIBILITY
    plat_printf_debug("DEBUG_VISIBILITY: Inserting symbol '%s' (module: %s, pub: %d, kind: %d)\n",
                     symbol.name, symbol.module_name ? symbol.module_name : "NULL",
                     (symbol.flags & SYMBOL_FLAG_PUB) != 0, (int)symbol.kind);
#endif
    // Resize if load factor exceeds 0.75
    if (symbol_count + 1 > bucket_count * 0.75) {
        resize();
    }

    u32 hash = hash_string(symbol.name);
    size_t index = hash % bucket_count;

    // Check for existing symbol and update if found
    for (SymbolEntry* entry = buckets[index]; entry != NULL; entry = entry->next) {
        if (plat_strcmp(entry->symbol.name, symbol.name) == 0) {
            if (symbol.module_name == NULL || entry->symbol.module_name == NULL ||
                plat_strcmp(entry->symbol.module_name, symbol.module_name) == 0) {
                entry->symbol = symbol;
                return;
            }
        }
    }

    // Allocate a new entry from the arena
    SymbolEntry* new_entry = (SymbolEntry*)arena.alloc(sizeof(SymbolEntry));
#ifdef MEASURE_MEMORY
    MemoryTracker::symbols++;
#endif
    new_entry->symbol = symbol;

    // Insert at the head of the bucket's linked list
    new_entry->next = buckets[index];
    buckets[index] = new_entry;
    symbol_count++;
}

Symbol* Scope::find(const char* name, const char* module_name) {
#ifdef DEBUG_VISIBILITY
    // Too noisy for general scope find, maybe skip or keep very brief
#endif
    u32 hash = hash_string(name);
    size_t index = hash % bucket_count;

    for (SymbolEntry* entry = buckets[index]; entry != NULL; entry = entry->next) {
        if (plat_strcmp(entry->symbol.name, name) == 0) {
            if (module_name == NULL || entry->symbol.module_name == NULL ||
                plat_strcmp(entry->symbol.module_name, module_name) == 0 ||
                plat_strcmp(entry->symbol.module_name, "builtin") == 0) {
                return &entry->symbol;
            }
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
    : arena_(arena), scopes(arena), all_scopes_(arena), current_module_(NULL), current_scope_level_(0)
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
#ifdef DEBUG_SYMBOL
    plat_printf_debug("[SYMBOL] INSERT: '%s' module=%s scope_level=%u current_depth=%zu\n",
                     symbol.name, 
                     symbol.module_name ? symbol.module_name : "NULL",
                     getCurrentScopeLevel(), 
                     scopes.length());
#endif
    // Check for redeclaration in the current scope.
    // If it's the global scope, we must check for collisions within the same module
    if (scopes.length() == 1) {
        if (scopes.back()->find(symbol.name, symbol.module_name)) {
            return false;
        }
    } else {
        if (lookupInCurrentScope(symbol.name)) {
            return false; // Symbol already exists.
        }
    }
    // Assign the current scope level to the symbol.
    symbol.scope_level = getCurrentScopeLevel();
    // Add the symbol to the current scope.
    scopes.back()->insert(symbol);
#ifdef DEBUG_SYMBOL
    Symbol* check = lookupInCurrentScope(symbol.name);
    plat_printf_debug("[SYMBOL] INSERT_POST: lookupInCurrentScope('%s') -> %p\n",
                     symbol.name, (void*)check);
#endif
    return true;
}

Symbol* SymbolTable::lookup(const char* name) {
#ifdef DEBUG_SYMBOL
    plat_printf_debug("[SYMBOL] LOOKUP: '%s' current_module=%s scopes=%zu\n",
                     name, 
                     current_module_ ? current_module_ : "NULL", 
                     scopes.length());
#endif
    // Search from the innermost scope to the outermost.
    for (int i = (int)scopes.length() - 1; i >= 0; --i) {
        const char* mod = (i == 0) ? current_module_ : NULL;
        Symbol* symbol = scopes[i]->find(name, mod);
        if (symbol) {
#ifdef DEBUG_VISIBILITY
            plat_printf_debug("DEBUG_VISIBILITY: SymbolTable::lookup('%s') in module '%s' level %d -> FOUND (module_name: %s, pub: %d)\n",
                             name, current_module_ ? current_module_ : "NULL", i,
                             symbol->module_name ? symbol->module_name : "NULL",
                             (symbol->flags & SYMBOL_FLAG_PUB) != 0);
#endif
            return symbol;
        }
    }
#ifdef DEBUG_VISIBILITY
    plat_printf_debug("DEBUG_VISIBILITY: SymbolTable::lookup('%s') in module '%s' -> NOT FOUND\n",
                     name, current_module_ ? current_module_ : "NULL");
#endif
    return NULL; // Not found in any scope.
}

Symbol* SymbolTable::lookupInCurrentScope(const char* name) {
    if (scopes.length() == 0) {
        return NULL;
    }
    const char* mod = (scopes.length() == 1) ? current_module_ : NULL;
    Symbol* sym = scopes.back()->find(name, mod);
#ifdef DEBUG_SYMBOL
    plat_printf_debug("[SYMBOL] LOOKUP_CURRENT: '%s' -> %p\n", name, (void*)sym);
#endif
    return sym;
}

Symbol* SymbolTable::lookupWithModule(const char* module_name, const char* symbol_name) {
    // Look directly into the global scope with the specified module name
    Symbol* result = NULL;
    if (scopes.length() > 0) {
        result = scopes[0]->find(symbol_name, module_name);
    }
#ifdef DEBUG_VISIBILITY
    plat_printf_debug("DEBUG_VISIBILITY: lookupWithModule(module: %s, symbol: %s) -> %p\n",
                     module_name, symbol_name, result);
#endif
    return result;
}

Symbol* SymbolTable::findInAnyScope(const char* name) {
    // Search all scopes ever created, from most recent to oldest.
    for (int i = (int)all_scopes_.length() - 1; i >= 0; --i) {
        // This is tricky because we don't know which module a scope belongs to here
        // But for any-scope lookup (used for things like forward references),
        // we probably want to ignore module filtering or use current module.
        Symbol* symbol = all_scopes_[i]->find(name, current_module_);
        if (symbol) {
            return symbol;
        }
    }
    return NULL;
}

unsigned int SymbolTable::getCurrentScopeLevel() const {
    return current_scope_level_;
}

void SymbolTable::registerTempSymbol(Symbol* symbol) {
    if (symbol && scopes.length() > 0) {
        symbol->scope_level = current_scope_level_;
        // Before inserting, if it's already there, we might want to update it or skip?
        // Usually lifting generates unique names, but catch prongs might reuse names.
        // For local temps, they MUST be unique.
        scopes.back()->insert(*symbol);
    }
}

void SymbolTable::dumpSymbols(const char* context) {
    plat_printf_debug("[SYMBOLS] === Dump: %s ===\n", context);
    for (size_t i = 0; i < scopes.length(); ++i) {
        plat_printf_debug("[SYMBOLS]  Scope level %d:\n", (int)i + 1);
        Scope* scope = scopes[i];
        for (size_t j = 0; j < scope->bucket_count; ++j) {
            Scope::SymbolEntry* entry = scope->buckets[j];
            while (entry) {
                Symbol& sym = entry->symbol;
                plat_printf_debug("[SYMBOLS]    name=%s kind=%d flags=0x%x\n",
                                 sym.name ? sym.name : "NULL", (int)sym.kind, sym.flags);
                entry = entry->next;
            }
        }
    }
    plat_printf_debug("[SYMBOLS] === End Dump ===\n");
}
