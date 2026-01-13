#include "token_supplier.hpp"
#include <cstring> // For memcpy

TokenSupplier::TokenSupplier(SourceManager& source_manager, StringInterner& interner, ArenaAllocator& arena)
    : source_manager_(source_manager),
      interner_(interner),
      arena_(arena),
      token_cache_(arena) {
}

TokenStream TokenSupplier::getTokensForFile(u32 file_id) {
    // Grow the cache if the file_id is out of bounds.
    while (token_cache_.length() <= file_id) {
        TokenStream empty_stream = { NULL, 0 };
        token_cache_.append(empty_stream);
    }

    // If the stream is not cached, tokenize it.
    if (token_cache_[file_id].tokens == NULL) {
        tokenizeAndCache(file_id);
    }

    return token_cache_[file_id];
}

void TokenSupplier::tokenizeAndCache(u32 file_id) {
    // 1. Tokenize into a temporary, resizable array.
    // This dynamic array's memory may be moved around by the arena as it grows,
    // which is fine because nothing external holds a pointer to its internal buffer.
    DynamicArray<Token> temp_tokens(arena_);
    Lexer lexer(source_manager_, interner_, arena_, file_id);

    while (true) {
        Token token = lexer.nextToken();
        temp_tokens.append(token);
        if (token.type == TOKEN_EOF) {
            break;
        }
    }

    // 2. Allocate a stable, perfectly-sized block of memory from the main arena.
    // This memory block will not be moved for the lifetime of the arena.
    size_t num_tokens = temp_tokens.length();
    size_t total_size = num_tokens * sizeof(Token);
    Token* stable_tokens = static_cast<Token*>(arena_.alloc(total_size));

    // 3. Copy the tokens from the temporary array to the stable block.
    if (stable_tokens && num_tokens > 0) {
        memcpy(stable_tokens, temp_tokens.getData(), total_size);
    }

    // 4. Cache the stable pointer and count.
    TokenStream final_stream = { stable_tokens, num_tokens };
    token_cache_[file_id] = final_stream;
}
