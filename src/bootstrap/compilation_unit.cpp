#include "compilation_unit.hpp"
#include "parser.hpp" // For Parser class definition
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

SymbolTable& CompilationUnit::getSymbolTable() {
    return symbol_table_;
}

ErrorHandler& CompilationUnit::getErrorHandler() {
    return error_handler_;
}

SourceManager& CompilationUnit::getSourceManager() {
    return source_manager_;
}

ArenaAllocator& CompilationUnit::getArena() {
    return arena_;
}
