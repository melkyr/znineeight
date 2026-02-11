#ifndef TOKEN_SUPPLIER_HPP
#define TOKEN_SUPPLIER_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "lexer.hpp"

/**
 * @struct TokenStream
 * @brief A non-owning view over a stable sequence of tokens.
 *
 * This struct provides a safe way to pass around the results of tokenization.
 * It contains a pointer to an array of tokens and the count of tokens in that
 * array. The memory for the tokens is guaranteed to be stable and is owned
 * by the TokenSupplier that created this stream.
 */
struct TokenStream {
    const Token* tokens;
    size_t count;
};

class TokenSupplier {
public:
    TokenSupplier(SourceManager& source_manager, StringInterner& interner, ArenaAllocator& arena);

    /**
     * @brief Gets a stable stream of tokens for a given source file.
     *
     * If the file has not been tokenized yet, this function will trigger the
     * lexer and cache the results in a stable memory location. Subsequent calls
     * for the same file_id will return the cached stream.
     *
     * @param file_id The ID of the source file.
     * @return A TokenStream containing a pointer to the tokens and the token count.
     */
    TokenStream getTokensForFile(u32 file_id);

    /**
     * @brief Resets the token supplier, clearing all cached token streams.
     * This should be called after resetting the arena used by the supplier.
     */
    void reset();

private:
    SourceManager& source_manager_;
    StringInterner& interner_;
    ArenaAllocator& arena_;

    // The cache now stores TokenStream objects, which are guaranteed to have stable pointers.
    DynamicArray<TokenStream> token_cache_;

    void tokenizeAndCache(u32 file_id);
};

#endif // TOKEN_SUPPLIER_HPP
