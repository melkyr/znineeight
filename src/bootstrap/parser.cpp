#include "parser.hpp"
#include <windows.h> // For OutputDebugStringA
#include <cstdlib>   // For abort()
#include <cstring>   // For strcmp

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

bool Parser::match(TokenType type) {
    if (is_at_end() || peek().type != type) {
        return false;
    }
    advance();
    return true;
}

void Parser::error(const char* msg) {
    // In a real compiler, we'd have a more sophisticated error reporting system.
    // For now, we'll just use the Windows debug output and abort.
    OutputDebugStringA("Parser Error: ");
    OutputDebugStringA(msg);
    OutputDebugStringA("\n");
    abort();
}

bool Parser::isPrimitiveType(const Token& token) {
    if (token.type != TOKEN_IDENTIFIER) {
        return false;
    }
    const char* id = token.value.identifier;
    return strcmp(id, "i32") == 0 || strcmp(id, "u8") == 0 || strcmp(id, "bool") == 0;
}

ASTNode* Parser::parseType() {
    if (match(TOKEN_STAR)) {
        return parsePointerType();
    }
    if (match(TOKEN_LBRACKET)) {
        return parseArrayType();
    }
    // Any identifier can be the name of a type.
    if (peek().type == TOKEN_IDENTIFIER) {
        return parsePrimitiveType(); // Re-using this helper as it does what we need.
    }
    error("Expected a type expression");
    return NULL; // Unreachable
}

ASTNode* Parser::parsePrimitiveType() {
    Token token = advance(); // Consume the identifier token
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_TYPE_NAME;
    node->loc = token.location;
    node->as.type_name.name = token.value.identifier;
    return node;
}

ASTNode* Parser::parsePointerType() {
    Token star_token = tokens_[current_index_ - 1]; // The '*' token
    ASTNode* base_type = parseType();

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_POINTER_TYPE;
    node->loc = star_token.location;
    node->as.pointer_type.base = base_type;

    return node;
}

ASTNode* Parser::parseArrayType() {
    Token lbracket_token = tokens_[current_index_ - 1]; // The '[' token
    ASTNode* size_expr = NULL;

    if (!match(TOKEN_RBRACKET)) {
        // For now, we only support integer literals as array sizes.
        // A full expression parser would be needed for more complex cases.
        if (peek().type == TOKEN_INTEGER_LITERAL) {
            Token size_token = advance();
            ASTNode* size_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
            size_node->type = NODE_INTEGER_LITERAL;
            size_node->loc = size_token.location;
            size_node->as.integer_literal.value = size_token.value.integer;
            size_expr = size_node;
        } else {
            error("Expected integer literal for array size");
        }

        if (!match(TOKEN_RBRACKET)) {
            error("Expected ']' after array size");
        }
    }

    ASTNode* element_type = parseType();

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_ARRAY_TYPE;
    node->loc = lbracket_token.location;
    node->as.array_type.element_type = element_type;
    node->as.array_type.size = size_expr; // NULL for slices

    return node;
}
