#include "compilation_unit.hpp"
#include "parser.hpp" // For Parser class definition
#include "type_system.hpp"
#include <cstring>   // For strlen
#include <new>       // For placement new
#include <cstdlib>   // For abort()

#if defined(_WIN32)
#include <windows.h> // For OutputDebugStringA
#endif

// Private helper to handle fatal errors
static void fatalError(const char* message) {
#if defined(_WIN32)
    OutputDebugStringA(message);
#else
    // On other platforms, no output, just abort.
#endif
    abort();
}

CompilationUnit::CompilationUnit(ArenaAllocator& arena, StringInterner& interner)
    : arena_(arena),
      interner_(interner),
      source_manager_(arena),
      symbol_table_(arena),
      error_handler_(source_manager_, arena),
      token_supplier_(source_manager_, interner_, arena) {
}

u32 CompilationUnit::addSource(const char* filename, const char* source) {
    return source_manager_.addFile(filename, source, strlen(source));
}

Parser* CompilationUnit::createParser(u32 file_id) {
    TokenStream token_stream = token_supplier_.getTokensForFile(file_id);
    if (!token_stream.tokens) {
        fatalError("CompilationUnit::createParser: Failed to retrieve tokens for file_id.");
        return NULL; // Will not be reached
    }

    void* mem = arena_.alloc(sizeof(Parser));
    return new (mem) Parser(token_stream.tokens, token_stream.count, &arena_, &symbol_table_);
}

/**
 * @brief Returns the symbol table for this compilation unit.
 * @return A reference to the SymbolTable.
 */
SymbolTable& CompilationUnit::getSymbolTable() {
    return symbol_table_;
}

ErrorHandler& CompilationUnit::getErrorHandler() {
    return error_handler_;
}

const ErrorHandler& CompilationUnit::getErrorHandler() const {
    return error_handler_;
}

SourceManager& CompilationUnit::getSourceManager() {
    return source_manager_;
}

ArenaAllocator& CompilationUnit::getArena() {
    return arena_;
}

CompilationOptions& CompilationUnit::getOptions() {
    return options_;
}

const CompilationOptions& CompilationUnit::getOptions() const {
    return options_;
}

void CompilationUnit::setOptions(const CompilationOptions& options) {
    options_ = options;
}

void CompilationUnit::injectRuntimeSymbols() {
    // arena_alloc(size: u32) -> *u8
    void* params_mem = arena_.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params = new (params_mem) DynamicArray<Type*>(arena_);
    params->append(get_g_type_u32());
    Type* ret_type = createPointerType(arena_, get_g_type_u8(), false);
    Type* fn_type = createFunctionType(arena_, params, ret_type);

    Symbol sym_alloc = SymbolBuilder(arena_)
        .withName(interner_.intern("arena_alloc"))
        .ofType(SYMBOL_FUNCTION)
        .withType(fn_type)
        .build();
    symbol_table_.insert(sym_alloc);

    // arena_free(ptr: *u8) -> void
    void* params_mem2 = arena_.alloc(sizeof(DynamicArray<Type*>));
    DynamicArray<Type*>* params2 = new (params_mem2) DynamicArray<Type*>(arena_);
    params2->append(createPointerType(arena_, get_g_type_u8(), false));
    Type* ret_type2 = get_g_type_void();
    Type* fn_type2 = createFunctionType(arena_, params2, ret_type2);

    Symbol sym_free = SymbolBuilder(arena_)
        .withName(interner_.intern("arena_free"))
        .ofType(SYMBOL_FUNCTION)
        .withType(fn_type2)
        .build();
    symbol_table_.insert(sym_free);
}
