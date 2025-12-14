#include "parser.hpp"
#include "ast.hpp"
#include <cstdlib>   // For abort()
#include <cstring>   // For strcmp
#include <cstdio>    // For fprintf, stderr

#ifdef _WIN32
#include <windows.h> // For OutputDebugStringA
#endif
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
    // Check if we are at the very last token, which should be EOF.
    // The loop in `create_parser_for_test` includes the EOF token in the count.
    return tokens_[current_index_].type == TOKEN_EOF;
}

bool Parser::match(TokenType type) {
    if (is_at_end() || peek().type != type) {
        return false;
    }
    advance();
    return true;
}

Token Parser::expect(TokenType type, const char* msg) {
    if (is_at_end() || peek().type != type) {
        error(msg);
    }
    return advance();
}

void Parser::error(const char* msg) {
#ifdef _WIN32
    // On Windows, use the debug output string function.
    OutputDebugStringA("Parser Error: ");
    OutputDebugStringA(msg);
    OutputDebugStringA("\n");
#else
    // On other platforms, print to standard error.
    fprintf(stderr, "Parser Error: %s\n", msg);
#endif
    abort();
}

ASTNode* Parser::parseExpression() {
    // This is a stub for now. It only handles integer literals.
    Token token = peek();
    if (token.type == TOKEN_INTEGER_LITERAL) {
        advance();
        ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        node->type = NODE_INTEGER_LITERAL;
        node->loc = token.location;
        node->as.integer_literal.value = token.value.integer;
        return node;
    }

    error("Expected an expression (currently only integer literals are supported)");
    return NULL; // Unreachable
}

ASTNode* Parser::parseVarDecl() {
    Token keyword_token = advance(); // Consume 'var' or 'const'
    bool is_const = keyword_token.type == TOKEN_CONST;
    bool is_mut = keyword_token.type == TOKEN_VAR;

    Token name_token = expect(TOKEN_IDENTIFIER, "Expected an identifier after 'var' or 'const'");
    expect(TOKEN_COLON, "Expected ':' after identifier in variable declaration");

    ASTNode* type_node = parseType();
    expect(TOKEN_EQUAL, "Expected '=' after type in variable declaration");
    ASTNode* initializer_node = parseExpression();
    expect(TOKEN_SEMICOLON, "Expected ';' after variable declaration");

    ASTVarDeclNode* var_decl = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
    var_decl->name = name_token.value.identifier;
    var_decl->type = type_node;
    var_decl->initializer = initializer_node;
    var_decl->is_const = is_const;
    var_decl->is_mut = is_mut;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_VAR_DECL;
    node->loc = keyword_token.location;
    node->as.var_decl = var_decl;

    return node;
}


ASTNode* Parser::parseType() {
    if (peek().type == TOKEN_STAR) {
        return parsePointerType();
    }
    if (peek().type == TOKEN_LBRACKET) {
        return parseArrayType();
    }
    if (peek().type == TOKEN_IDENTIFIER) {
        Token type_name_token = advance();
        ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        node->type = NODE_TYPE_NAME;
        node->loc = type_name_token.location;
        node->as.type_name.name = type_name_token.value.identifier;
        return node;
    }
    error("Expected a type expression");
    return NULL; // Unreachable
}

ASTNode* Parser::parsePointerType() {
    Token star_token = advance(); // Consume '*'
    ASTNode* base_type = parseType();

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_POINTER_TYPE;
    node->loc = star_token.location;
    node->as.pointer_type.base = base_type;

    return node;
}

ASTNode* Parser::parseArrayType() {
    Token lbracket_token = advance(); // Consume '['
    ASTNode* size_expr = NULL;

    if (peek().type != TOKEN_RBRACKET) {
        // As a simplification for now, we only support integer literals as array sizes.
        size_expr = parseExpression();
    }

    expect(TOKEN_RBRACKET, "Expected ']' after array size or for slice");

    ASTNode* element_type = parseType();

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_ARRAY_TYPE;
    node->loc = lbracket_token.location;
    node->as.array_type.element_type = element_type;
    node->as.array_type.size = size_expr; // Will be NULL for slices

    return node;
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
