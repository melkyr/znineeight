#include "symbol_table.hpp"
#include "platform.hpp"
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
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("DEBUG_VISIBILITY: Inserting symbol '%s' (module: %s, pub: %d, kind: %d)\n",
                     symbol.name, symbol.module_name ? symbol.module_name : "NULL",
                     (symbol.flags & SYMBOL_FLAG_PUB) != 0, (int)symbol.kind);
#endif
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
            bool same_module = (symbol.module_name == NULL || entry->symbol.module_name == NULL ||
                                plat_strcmp(entry->symbol.module_name, symbol.module_name) == 0);
            if (same_module) {
                // Traverse same-name chain to check for same kind
                SymbolEntry* current = entry;
                while (current) {
                    if (current->symbol.kind == symbol.kind) {
                        current->symbol = symbol; // Same kind: overwrite
                        return;
                    }
                    if (!current->next_same_name) break;
                    current = current->next_same_name;
                }

                // Different kind: append to same-name chain
                SymbolEntry* new_entry = (SymbolEntry*)arena.alloc(sizeof(SymbolEntry));
#ifdef MEASURE_MEMORY
                MemoryTracker::symbols++;
#endif
                new_entry->symbol = symbol;
                new_entry->next = NULL; // It's not the head of the bucket
                new_entry->next_same_name = NULL;
                current->next_same_name = new_entry;
                symbol_count++;
                return;
            }
        }
    }

    // Allocate a new entry from the arena (head of bucket)
    SymbolEntry* new_entry = (SymbolEntry*)arena.alloc(sizeof(SymbolEntry));
#ifdef MEASURE_MEMORY
    MemoryTracker::symbols++;
#endif
    new_entry->symbol = symbol;
    new_entry->next_same_name = NULL;

    // Insert at the head of the bucket's linked list
    new_entry->next = buckets[index];
    buckets[index] = new_entry;
    symbol_count++;
}

Symbol* Scope::find(const char* name, const char* module_name, SymbolType kind) {
    u32 hash = hash_string(name);
    size_t index = hash % bucket_count;

    for (SymbolEntry* entry = buckets[index]; entry != NULL; entry = entry->next) {
        if (plat_strcmp(entry->symbol.name, name) == 0) {
            bool module_matches = false;
            if (module_name == NULL || entry->symbol.module_name == NULL) {
                module_matches = true;
            } else if (plat_strcmp(entry->symbol.module_name, module_name) == 0) {
                module_matches = true;
            } else if (plat_strcmp(entry->symbol.module_name, "builtin") == 0) {
                module_matches = true;
            }

            if (module_matches) {
                // Search same-name chain for requested kind
                for (SymbolEntry* current = entry; current != NULL; current = current->next_same_name) {
                    if (kind == SYMBOL_UNKNOWN || current->symbol.kind == kind) {
                        return &current->symbol;
                    }
                }
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
            SymbolEntry* next = entry->next; // Save next entry (next head of bucket)

            u32 hash = hash_string(entry->symbol.name);
            size_t new_index = hash % new_bucket_count;

            // Insert into the new bucket (entry is head of a same-name chain)
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
#ifdef DEBUG_SYMBOL
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] ENTER_SCOPE depth=%lu\n", (unsigned long)scopes.length());
#endif
#endif
}

void SymbolTable::exitScope() {
    if (scopes.length() > 1) { // Do not exit the global scope.
#ifdef DEBUG_SYMBOL
        #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] EXIT_SCOPE depth=%lu\n", (unsigned long)scopes.length());
#endif
#endif
        scopes.pop_back();
        current_scope_level_--;
    }
}

bool SymbolTable::insert(Symbol& symbol) {
#ifdef DEBUG_SYMBOL
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] INSERT '%s' module=%s scope_level=%u depth=%lu\n", symbol.name, symbol.module_name ? symbol.module_name : "NULL", symbol.scope_level, (unsigned long)scopes.length());
#endif
#endif
    // Check for redeclaration in the current scope.
    // If it's the global scope, we must check for collisions within the same module
    if (scopes.length() == 1) {
        if (scopes.back()->find(symbol.name, symbol.module_name, symbol.kind)) {
            return false;
        }
    } else {
        if (lookupInCurrentScope(symbol.name, symbol.kind)) {
            return false; // Symbol already exists.
        }
    }
    // Assign the current scope level to the symbol.
    symbol.scope_level = getCurrentScopeLevel();
    // Add the symbol to the current scope.
#ifdef DEBUG_SYMBOL
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] INSERTED '%s' into scope level %lu\n", symbol.name, (unsigned long)scopes.length());
#endif
#endif
    scopes.back()->insert(symbol);
    return true;
}

Symbol* SymbolTable::lookup(const char* name, SymbolType kind) {
#ifdef DEBUG_SYMBOL
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] LOOKUP '%s' (kind=%d) current_module=%s scopes=%lu\n", name, (int)kind, current_module_ ? current_module_ : "NULL", (unsigned long)scopes.length());
#endif
#endif
    // Search from the innermost scope to the outermost.
    for (int i = (int)scopes.length() - 1; i >= 0; --i) {
        // Try local lookup (NULL module) first in all scopes
        Symbol* symbol = scopes[i]->find(name, NULL, kind);
        if (!symbol) {
            // Then try current module lookup
            symbol = scopes[i]->find(name, current_module_, kind);
        }

        if (symbol) {
#ifdef DEBUG_SYMBOL
            #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] FOUND '%s' at level %d module=%s\n", name, i, symbol->module_name ? symbol->module_name : "NULL");
#endif
#endif
#ifdef DEBUG_VISIBILITY
            #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("DEBUG_VISIBILITY: SymbolTable::lookup('%s') in module '%s' level %d -> FOUND (module_name: %s, pub: %d)\n",
                             name, current_module_ ? current_module_ : "NULL", i,
                             symbol->module_name ? symbol->module_name : "NULL",
                             (symbol->flags & SYMBOL_FLAG_PUB) != 0);
#endif
#endif
            return symbol;
        }
    }
#ifdef DEBUG_SYMBOL
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] NOT FOUND '%s'\n", name);
#endif
#endif
#ifdef DEBUG_VISIBILITY
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("DEBUG_VISIBILITY: SymbolTable::lookup('%s') in module '%s' -> NOT FOUND\n",
                     name, current_module_ ? current_module_ : "NULL");
#endif
#endif
    return NULL; // Not found in any scope.
}

Symbol* SymbolTable::lookupInCurrentScope(const char* name, SymbolType kind) {
    if (scopes.length() == 0) {
        return NULL;
    }
    // For local scopes (depth > 1), we ONLY want local variables (module_name == NULL).
    // For the global scope (depth == 1), we want module-level symbols.
    const char* mod_filter = (scopes.length() == 1) ? current_module_ : NULL;
#ifdef DEBUG_SYMBOL
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] LOOKUP_IN_CURRENT_SCOPE '%s' (kind=%d) depth=%lu mod_filter=%s\n",
                     name, (int)kind, (unsigned long)scopes.length(), mod_filter ? mod_filter : "NULL");
#endif
#endif
    Symbol* sym = scopes.back()->find(name, mod_filter, kind);

#ifdef DEBUG_SYMBOL
    if (sym) {
        #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] FOUND_IN_CURRENT_SCOPE '%s' module=%s\n",
                         name, sym->module_name ? sym->module_name : "NULL");
#endif
    } else {
        #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOL] NOT_FOUND_IN_CURRENT_SCOPE '%s'\n", name);
#endif
    }
#endif

    return sym;
}

Symbol* SymbolTable::lookupWithModule(const char* module_name, const char* symbol_name, SymbolType kind) {
    // Look directly into the global scope with the specified module name
    Symbol* result = NULL;
    if (scopes.length() > 0) {
        result = scopes[0]->find(symbol_name, module_name, kind);
    }
#ifdef DEBUG_VISIBILITY
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("DEBUG_VISIBILITY: lookupWithModule(module: %s, symbol: %s) -> %p\n",
                     module_name, symbol_name, result);
#endif
#endif
    return result;
}

Symbol* SymbolTable::findInAnyScope(const char* name, const char* preferred_module, SymbolType kind) {
    Symbol* local_fallback = NULL;

    // Search all scopes ever created, from most recent to oldest.
    for (int i = (int)all_scopes_.length() - 1; i >= 0; --i) {
        // 1. Try preferred module first
        if (preferred_module) {
            Symbol* sym = all_scopes_[i]->find(name, preferred_module, kind);
            if (sym) return sym;
        }

        // 2. Try NULL module (local variables)
        if (!local_fallback) {
            local_fallback = all_scopes_[i]->find(name, NULL, kind);
        }

        // 3. Try current module
        if (current_module_ && current_module_ != preferred_module) {
            Symbol* sym = all_scopes_[i]->find(name, current_module_, kind);
            if (sym) return sym;
        }
    }
    return local_fallback;
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
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOLS] === Dump: %s ===\n", context);
#endif
    for (size_t i = 0; i < scopes.length(); ++i) {
        #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOLS]  Scope level %d:\n", (int)i + 1);
#endif
        Scope* scope = scopes[i];
        for (size_t j = 0; j < scope->bucket_count; ++j) {
            Scope::SymbolEntry* entry = scope->buckets[j];
            while (entry) {
                Symbol& sym = entry->symbol;
                #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOLS]    name=%s kind=%d flags=0x%x\n",
                                 sym.name ? sym.name : "NULL", (int)sym.kind, sym.flags);
#endif
                entry = entry->next;
            }
        }
    }
    #ifdef Z98_ENABLE_DEBUG_LOGS
    plat_printf_debug("[SYMBOLS] === End Dump ===\n");
#endif
}
