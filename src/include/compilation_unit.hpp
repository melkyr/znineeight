#ifndef COMPILATION_UNIT_HPP
#define COMPILATION_UNIT_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "symbol_table.hpp" // Added include
#include <cstring> // For strlen

class CompilationUnit {
public:
    CompilationUnit(ArenaAllocator& arena, StringInterner& interner)
        : arena_(arena),
          interner_(interner),
          source_manager_(arena),
          symbol_table_(arena) {} // Initialize SymbolTable

    u32 addSource(const char* filename, const char* source) {
        return source_manager_.addFile(filename, source, strlen(source));
    }

    Parser createParser(u32 file_id) {
        Lexer lexer(source_manager_, interner_, arena_, file_id);
        DynamicArray<Token> tokens(arena_);
        while (true) {
            Token token = lexer.nextToken();
            tokens.append(token);
            if (token.type == TOKEN_EOF) {
                break;
            }
        }
        return Parser(tokens.getData(), tokens.length(), &arena_);
    }

    /**
     * @brief Gets a reference to the symbol table for this compilation unit.
     */
    SymbolTable& getSymbolTable() {
        return symbol_table_;
    }

private:
    ArenaAllocator& arena_;
    StringInterner& interner_;
    SourceManager source_manager_;
    SymbolTable symbol_table_; // Added member
};

#endif // COMPILATION_UNIT_HPP
