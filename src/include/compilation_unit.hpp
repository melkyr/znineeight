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
#include <cstring> // For strlen

struct FileTokenCache {
    u32 file_id;
    Token* tokens;
    u32 token_count;

    FileTokenCache()
        : file_id(0), tokens(NULL), token_count(0) {}
};

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
        return source_manager_.addFile(filename, source, strlen(source));
    }

    Parser* createParser(u32 file_id) {
        // Check cache FIRST
        for (u32 i = 0; i < token_cache_.length(); ++i) {
            if (token_cache_[i].file_id == file_id) {
                void* mem = arena_.alloc(sizeof(Parser));
                return new (mem) Parser(
                    token_cache_[i].tokens,
                    token_cache_[i].token_count,
                    &arena_,
                    &symbol_table_
                );
            }
        }

        // To be memory efficient, we perform a two-pass tokenization.
        // Pass 1: Use a temporary, isolated arena to count tokens without affecting the main arena.
        size_t token_count = 0;
        {
            ArenaAllocator counter_arena(1024); // A small temp arena for the counting pass.
            StringInterner counter_interner(counter_arena);
            Lexer counter_lexer(source_manager_, counter_interner, counter_arena, file_id);

            while (true) {
                Token token = counter_lexer.nextToken();
                token_count++;
                if (token.type == TOKEN_EOF) {
                    break;
                }
            }
        } // temp arena and interner are destroyed here.

        // Pass 2: Now that we have the exact count, allocate a perfectly sized
        // buffer from the main arena and lex for real.
        Token* token_data = arena_.allocArray<Token>(token_count);

        Lexer lexer(source_manager_, interner_, arena_, file_id);
        for (size_t i = 0; i < token_count; ++i) {
            token_data[i] = lexer.nextToken();
        }

        // Cache the newly lexed tokens.
        FileTokenCache entry;
        entry.file_id = file_id;
        entry.tokens = token_data;
        entry.token_count = token_count;
        token_cache_.append(entry);

        void* mem = arena_.alloc(sizeof(Parser));
        return new (mem) Parser(entry.tokens, entry.token_count, &arena_, &symbol_table_);
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
    DynamicArray<FileTokenCache> token_cache_;
};

#endif // COMPILATION_UNIT_HPP
