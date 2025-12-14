#include "parser.hpp"

Parser::Parser(Token* tokens, size_t count, ArenaAllocator* arena)
    : tokens_(tokens), token_count_(count), current_index_(0), arena_(arena) {
    assert(tokens_ != NULL && "Token stream cannot be null");
    assert(arena_ != NULL && "Arena allocator is required");
}

Token Parser::advance() {
    assert(!is_at_end() && "Cannot advance beyond the end of the token stream");
    return tokens_[current_index_++];
}

const Token& Parser::peek() const {
    assert(!is_at_end() && "Cannot peek beyond the end of the token stream");
    return tokens_[current_index_];
}

bool Parser::is_at_end() const {
    return current_index_ >= token_count_;
}
