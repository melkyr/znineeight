#include "parser.hpp"
#include "ast.hpp"
#include <cstdlib>   // For abort()
#include <cstring>   // For strcmp
#include <new>       // For placement new

#ifdef _WIN32
#include <windows.h> // For OutputDebugStringA
#endif

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
#endif
    // For non-Windows builds, this will just abort.
    // The test environment doesn't have a C runtime for fprintf,
    // and for the bootstrap compiler, we only officially support Windows.
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

/**
 * @brief Parses a top-level variable declaration (`var` or `const`).
 *        Grammar: `('var'|'const') IDENT ':' type_expr '=' expr ';'`
 * @note This parser currently only supports integer literals for the initializer expression.
 * @return A pointer to the ASTNode representing the variable declaration.
 */
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

/**
 * @brief Parses a defer statement.
 *        Grammar: `'defer' block_statement`
 * @return A pointer to the ASTNode representing the defer statement.
 */
ASTNode* Parser::parseDeferStatement() {
    Token defer_token = expect(TOKEN_DEFER, "Expected 'defer' keyword");

    // The statement following 'defer' must be a block statement.
    ASTNode* statement = parseBlockStatement();

    ASTDeferStmtNode defer_stmt;
    defer_stmt.statement = statement;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_DEFER_STMT;
    node->loc = defer_token.location;
    node->as.defer_stmt = defer_stmt;

    return node;
}


/**
 * @brief Parses a top-level function declaration.
 *        Grammar: `fn IDENT '(' ')' '->' type_expr '{' '}'`
 * @note This parser currently enforces that the parameter list and function body are empty.
 * @return A pointer to the ASTNode representing the function declaration.
 */
ASTNode* Parser::parseFnDecl() {
    Token fn_token = expect(TOKEN_FN, "Expected 'fn' keyword");
    Token name_token = expect(TOKEN_IDENTIFIER, "Expected function name after 'fn'");

    expect(TOKEN_LPAREN, "Expected '(' after function name");
    if (peek().type != TOKEN_RPAREN) {
        error("Non-empty parameter lists are not yet supported");
    }
    expect(TOKEN_RPAREN, "Expected ')' after parameter list");

    expect(TOKEN_ARROW, "Expected '->' for return type in function declaration");
    ASTNode* return_type_node = parseType();

    Token lbrace_token = expect(TOKEN_LBRACE, "Expected '{' for function body");
    if (peek().type != TOKEN_RBRACE) {
        error("Non-empty function bodies are not yet supported");
    }
    expect(TOKEN_RBRACE, "Expected '}' to close function body");

    // Create the empty body node
    ASTBlockStmtNode body_stmt;
    body_stmt.statements = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    new (body_stmt.statements) DynamicArray<ASTNode*>(*arena_); // Placement new

    ASTNode* body_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    body_node->type = NODE_BLOCK_STMT;
    body_node->loc = lbrace_token.location;
    body_node->as.block_stmt = body_stmt;

    // Create the function declaration node
    ASTFnDeclNode* fn_decl = (ASTFnDeclNode*)arena_->alloc(sizeof(ASTFnDeclNode));
    fn_decl->name = name_token.value.identifier;
    fn_decl->return_type = return_type_node;
    fn_decl->body = body_node;

    // Initialize the parameters array
    fn_decl->params = (DynamicArray<ASTParamDeclNode*>*)arena_->alloc(sizeof(DynamicArray<ASTParamDeclNode*>));
    new (fn_decl->params) DynamicArray<ASTParamDeclNode*>(*arena_);

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_FN_DECL;
    node->loc = fn_token.location;
    node->as.fn_decl = fn_decl;

    return node;
}

/**
 * @brief Parses a single statement.
 *
 * This function acts as a dispatcher. It looks at the current token and decides
 * which specific parsing function to call. It currently handles `if`, `while`,
 * block (`{}`), and empty (`;`) statements.
 *
 * @return A pointer to the ASTNode representing the parsed statement.
 */
ASTNode* Parser::parseStatement() {
    switch (peek().type) {
        case TOKEN_DEFER:
            return parseDeferStatement();
        case TOKEN_IF:
            return parseIfStatement();
        case TOKEN_WHILE:
            return parseWhileStatement();
        case TOKEN_LBRACE:
            return parseBlockStatement();
        case TOKEN_SEMICOLON: {
            Token semi_token = advance(); // Consume ';'
            ASTNode* empty_stmt_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
            empty_stmt_node->type = NODE_EMPTY_STMT;
            empty_stmt_node->loc = semi_token.location;
            return empty_stmt_node;
        }
        default:
            error("Expected a statement");
            return NULL; // Unreachable
    }
}

ASTNode* Parser::parseBlockStatement() {
    Token lbrace_token = expect(TOKEN_LBRACE, "Expected '{' to start a block");

    DynamicArray<ASTNode*>* statements = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    new (statements) DynamicArray<ASTNode*>(*arena_); // Placement new

    while (!is_at_end() && peek().type != TOKEN_RBRACE) {
        statements->append(parseStatement());
    }

    expect(TOKEN_RBRACE, "Expected '}' to end a block");

    ASTNode* block_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    block_node->type = NODE_BLOCK_STMT;
    block_node->loc = lbrace_token.location;
    block_node->as.block_stmt.statements = statements;

    return block_node;
}

/**
 * @brief Parses an if statement with an optional else clause.
 *        Grammar: `'if' '(' expr ')' block_statement ('else' block_statement)?`
 * @return A pointer to the ASTNode representing the if statement.
 */
ASTNode* Parser::parseIfStatement() {
    Token if_token = expect(TOKEN_IF, "Expected 'if' keyword");
    expect(TOKEN_LPAREN, "Expected '(' after 'if'");
    ASTNode* condition = parseExpression();
    expect(TOKEN_RPAREN, "Expected ')' after if condition");

    ASTNode* then_block = parseBlockStatement();
    ASTNode* else_block = NULL;

    if (match(TOKEN_ELSE)) {
        else_block = parseBlockStatement();
    }

    ASTIfStmtNode* if_stmt_node = (ASTIfStmtNode*)arena_->alloc(sizeof(ASTIfStmtNode));
    if_stmt_node->condition = condition;
    if_stmt_node->then_block = then_block;
    if_stmt_node->else_block = else_block;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_IF_STMT;
    node->loc = if_token.location;
    node->as.if_stmt = if_stmt_node;

    return node;
}

/**
 * @brief Parses a while statement.
 *        Grammar: `'while' '(' expr ')' block_statement`
 * @return A pointer to the ASTNode representing the while statement.
 */
ASTNode* Parser::parseWhileStatement() {
    Token while_token = expect(TOKEN_WHILE, "Expected 'while' keyword");
    expect(TOKEN_LPAREN, "Expected '(' after 'while'");
    ASTNode* condition = parseExpression();
    expect(TOKEN_RPAREN, "Expected ')' after while condition");

    ASTNode* body = parseBlockStatement();

    ASTWhileStmtNode while_stmt_node;
    while_stmt_node.condition = condition;
    while_stmt_node.body = body;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_WHILE_STMT;
    node->loc = while_token.location;
    node->as.while_stmt = while_stmt_node;

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
