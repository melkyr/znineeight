#ifndef SYMBOL_TABLE_HPP
#define SYMBOL_TABLE_HPP

#include "common.hpp"
#include "ast.hpp"
#include "memory.hpp"
#include "source_manager.hpp"

// Forward declarations
class ArenaAllocator;
struct Type;

enum SymbolType {
    SYMBOL_VARIABLE,
    SYMBOL_FUNCTION,
    SYMBOL_TYPE,
    SYMBOL_UNION_TYPE
};

enum SymbolFlag {
    SYMBOL_FLAG_LOCAL   = (1 << 0),  // Stack-allocated variable/parameter
    SYMBOL_FLAG_STATIC  = (1 << 1),  // Static storage
    SYMBOL_FLAG_PARAM   = (1 << 2),  // Function parameter
    SYMBOL_FLAG_GLOBAL  = (1 << 3),  // Global variable
    SYMBOL_FLAG_EXTERN  = (1 << 4),  // Extern linkage
    SYMBOL_FLAG_CONST   = (1 << 5)   // Immutable symbol
};

struct Symbol {
    const char* name;
    const char* module_name; // NULL for local or 'main' module
    const char* mangled_name;
    SymbolType kind;
    Type* symbol_type; // The actual type of the symbol (e.g., i32, *u8)
    SourceLocation location;
    void* details;
    unsigned int scope_level; // Set by SymbolTable on insertion
    unsigned int flags;        // Bitmask of SymbolFlag
    bool is_generic;           // True if it's a generic function
};

class SymbolBuilder {
    ArenaAllocator& arena_;
    Symbol temp_symbol_;

public:
    SymbolBuilder(ArenaAllocator& arena);
    SymbolBuilder& withName(const char* name);
    SymbolBuilder& withModule(const char* module_name);
    SymbolBuilder& withMangledName(const char* mangled_name);
    SymbolBuilder& ofType(SymbolType type);
    SymbolBuilder& withType(Type* symbol_type);
    SymbolBuilder& atLocation(const SourceLocation& loc);
    SymbolBuilder& definedBy(void* details);
    SymbolBuilder& inScope(unsigned int level);
    SymbolBuilder& withFlags(unsigned int flags);
    SymbolBuilder& asGeneric(bool generic = true);
    Symbol build();
};

struct Scope {
    struct SymbolEntry {
        Symbol symbol;
        SymbolEntry* next;
    };

    DynamicArray<SymbolEntry*> buckets;
    size_t symbol_count;
    size_t bucket_count;
    ArenaAllocator& arena;

    Scope(ArenaAllocator& arena, size_t initial_bucket_count = 4);
    void insert(Symbol& symbol);
    Symbol* find(const char* name, const char* module_name = NULL);
    void resize();
};

class SymbolTable {
    ArenaAllocator& arena_;
    DynamicArray<Scope*> scopes;
    DynamicArray<Scope*> all_scopes_; // Persist all scopes for subsequent passes
    const char* current_module_;
    unsigned int current_scope_level_;

public:
    SymbolTable(ArenaAllocator& arena);
    void setCurrentModule(const char* module_name) { current_module_ = module_name; }
    void enterScope();
    void exitScope();
    bool insert(Symbol& symbol);
    Symbol* lookup(const char* name);
    Symbol* lookupInCurrentScope(const char* name);
    Symbol* lookupWithModule(const char* module_name, const char* symbol_name);
    Symbol* findInAnyScope(const char* name); // Used by subsequent passes
    unsigned int getCurrentScopeLevel() const;
};

#endif // SYMBOL_TABLE_HPP
