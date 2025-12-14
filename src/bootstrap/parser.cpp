#include "parser.hpp"
#include <cstdio>  // For vsnprintf
#include <cstdarg> // For va_list, va_start, va_end
#include <cstring> // For strcmp

// A simple helper to get the string representation of a token type.
// In a real compiler, this would be more robust.
const char* tokenTypeToString(TokenType type) {
    // This is a minimal implementation for the error message.
    // A full implementation would have a mapping for all token types.
    switch (type) {
        case TOKEN_CONST: return "const";
        case TOKEN_VAR: return "var";
        case TOKEN_FN: return "fn";
        case TOKEN_IDENTIFIER: return "identifier";
        case TOKEN_EOF: return "end of file";
        default: return "token";
    }
}

Parser::Parser(Token* tokens, size_t count, ArenaAllocator* arena)
    : tokens_(tokens), token_count_(count), current_index_(0), arena_(arena), errors_(*arena) {
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

bool Parser::match(TokenType type) {
    if (is_at_end() || peek().type != type) {
        return false;
    }
    advance();
    return true;
}

Token Parser::expect(TokenType expected_type) {
    if (is_at_end() || peek().type != expected_type) {
        // Uh oh, syntax error.
        char buffer[256];
        sprintf(buffer, "Syntax Error: Expected token '%s', but got '%s'",
                tokenTypeToString(expected_type),
                tokenTypeToString(peek().type));

        // The error message is now on the stack. We need to allocate it
        // from the arena to ensure its lifetime.
        size_t msg_len = strlen(buffer) + 1;
        char* arena_msg = (char*)arena_->alloc(msg_len);
        memcpy(arena_msg, buffer, msg_len);

        reportError(peek(), arena_msg);
        return peek(); // Return the mismatched token without advancing.
    }
    return advance(); // Success, consume and return the token.
}

const DynamicArray<ErrorReport>* Parser::getErrors() const {
    return &errors_;
}

void Parser::reportError(const Token& token, const char* message) {
    ErrorReport report;
    report.token = token;
    report.message = message;
    errors_.append(report);
}
