#ifndef TOKEN_SUPPLIER_HPP
#define TOKEN_SUPPLIER_HPP

#include "common.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "source_manager.hpp"
#include "lexer.hpp"

class TokenSupplier {
public:
    TokenSupplier(SourceManager& source_manager, StringInterner& interner, ArenaAllocator& arena);

    const Token* getTokensForFile(u32 file_id);

    size_t getTokenCountForFile(u32 file_id);

private:
    SourceManager& source_manager_;
    StringInterner& interner_;
    ArenaAllocator& arena_;
    DynamicArray<DynamicArray<Token>*> token_cache_;

    void tokenizeAndCache(u32 file_id);
};

#endif // TOKEN_SUPPLIER_HPP
