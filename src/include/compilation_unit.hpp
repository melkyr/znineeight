#ifndef COMPILATION_UNIT_HPP
#define COMPILATION_UNIT_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "symbol_table.hpp"
#include "error_handler.hpp"
#include "token_supplier.hpp"

// Forward-declare Parser to avoid including parser.hpp in this header.
class Parser;

class CompilationUnit {
public:
    CompilationUnit(ArenaAllocator& arena, StringInterner& interner);

    u32 addSource(const char* filename, const char* source);

    Parser* createParser(u32 file_id);

    SymbolTable& getSymbolTable();
    ErrorHandler& getErrorHandler();
    SourceManager& getSourceManager();
    ArenaAllocator& getArena();

private:
    ArenaAllocator& arena_;
    StringInterner& interner_;
    SourceManager source_manager_;
    SymbolTable symbol_table_;
    ErrorHandler error_handler_;
    TokenSupplier token_supplier_;
};

#endif // COMPILATION_UNIT_HPP
