#ifndef COMPILATION_UNIT_HPP
#define COMPILATION_UNIT_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "lexer.hpp"
#include "parser.hpp"
#include "symbol_table.hpp"
#include "error_handler.hpp"
#include "lexer.hpp"
#include <cstring> // For strlen
#include <new>     // For placement new

class CompilationUnit {
public:
    CompilationUnit(ArenaAllocator& arena, StringInterner& interner)
        : arena_(arena),
          interner_(interner),
          source_manager_(arena),
          symbol_table_(arena),
          error_handler_(source_manager_, arena),
          token_cache_(arena) {}

    u32 addSource(const char* filename, const char* source) {
        u32 file_id = source_manager_.addFile(filename, source, strlen(source));
        while (token_cache_.length() <= file_id) {
            void* mem = arena_.alloc(sizeof(DynamicArray<Token>));
            token_cache_.append(new (mem) DynamicArray<Token>(arena_));
        }
        return file_id;
    }

    Parser* createParser(u32 file_id) {
        if (file_id >= token_cache_.length()) {
            return NULL;
        }

        DynamicArray<Token>* tokens = token_cache_[file_id];
        if (tokens->length() == 0) {
            Lexer lexer(source_manager_, interner_, arena_, file_id);
            while (true) {
                Token token = lexer.nextToken();
                tokens->append(token);
                if (token.type == TOKEN_EOF) {
                    break;
                }
            }
        }

        void* mem = arena_.alloc(sizeof(Parser));
        return new (mem) Parser(tokens->getData(), tokens->length(), &arena_, &symbol_table_);
    }

    /**
     * @brief Gets a reference to the symbol table for this compilation unit.
     */
    SymbolTable& getSymbolTable() {
        return symbol_table_;
    }

    ErrorHandler& getErrorHandler() {
        return error_handler_;
    }

    SourceManager& getSourceManager() {
        return source_manager_;
    }

    ArenaAllocator& getArena() {
        return arena_;
    }
private:
    ArenaAllocator& arena_;
    StringInterner& interner_;
    SourceManager source_manager_;
    SymbolTable symbol_table_;
    ErrorHandler error_handler_;
    DynamicArray<DynamicArray<Token>*> token_cache_;
};

#endif // COMPILATION_UNIT_HPP
