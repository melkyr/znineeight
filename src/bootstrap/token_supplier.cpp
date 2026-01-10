#include "token_supplier.hpp"
#include <new>

TokenSupplier::TokenSupplier(SourceManager& source_manager, StringInterner& interner, ArenaAllocator& arena)
    : source_manager_(source_manager),
      interner_(interner),
      arena_(arena),
      token_cache_(arena) {
}

const Token* TokenSupplier::getTokensForFile(u32 file_id) {
    while (token_cache_.length() <= file_id) {
        void* mem = arena_.alloc(sizeof(DynamicArray<Token>));
        token_cache_.append(new (mem) DynamicArray<Token>(arena_));
    }

    DynamicArray<Token>* tokens = token_cache_[file_id];
    if (tokens->length() == 0) {
        tokenizeAndCache(file_id);
    }

    return tokens->getData();
}

size_t TokenSupplier::getTokenCountForFile(u32 file_id) {
    if (file_id >= token_cache_.length()) {
        return 0;
    }
    return token_cache_[file_id]->length();
}

void TokenSupplier::tokenizeAndCache(u32 file_id) {
    if (file_id >= token_cache_.length()) {
        return;
    }

    DynamicArray<Token>* tokens = token_cache_[file_id];
    Lexer lexer(source_manager_, interner_, arena_, file_id);

    while (true) {
        Token token = lexer.nextToken();
        tokens->append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }
}
