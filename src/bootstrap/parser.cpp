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
    // This can be called when current_index_ points to the EOF token.
    // The is_at_end() check uses this, and the expression parser needs to be able to
    // peek at the EOF token to know when to stop.
    assert(current_index_ < token_count_ && "Cannot peek past the end of the token buffer");
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

/**
 * @brief Parses a primary expression from the token stream.
 *
 * Primary expressions are the highest-precedence expressions and form the
 * base of the expression parsing hierarchy. This function handles literals
 * (integers, floats, chars, strings), identifiers, and expressions grouped
 * by parentheses.
 *
 * Grammar:
 * `primary_expr ::= INTEGER | FLOAT | CHAR | STRING | IDENTIFIER | '(' expression ')'`
 *
 * @return A pointer to an `ASTNode` representing the parsed primary expression.
 *         The node is allocated from the parser's arena.
 * @note If an unexpected token is encountered, this function will call `error()`
 *       which aborts the compilation process.
 */
ASTNode* Parser::parsePrimaryExpr() {
    Token token = peek();
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->loc = token.location;

    switch (token.type) {
        case TOKEN_INTEGER_LITERAL:
            advance();
            node->type = NODE_INTEGER_LITERAL;
            node->as.integer_literal.value = token.value.integer;
            return node;
        case TOKEN_FLOAT_LITERAL:
            advance();
            node->type = NODE_FLOAT_LITERAL;
            node->as.float_literal.value = token.value.floating_point;
            return node;
        case TOKEN_CHAR_LITERAL:
            advance();
            node->type = NODE_CHAR_LITERAL;
            node->as.char_literal.value = token.value.character;
            return node;
        case TOKEN_STRING_LITERAL:
            advance();
            node->type = NODE_STRING_LITERAL;
            node->as.string_literal.value = token.value.identifier;
            return node;
        case TOKEN_IDENTIFIER:
            advance();
            node->type = NODE_IDENTIFIER;
            node->as.identifier.name = token.value.identifier;
            return node;
        case TOKEN_LPAREN: {
            advance(); // consume '('
            ASTNode* expr_node = parseExpression();
            expect(TOKEN_RPAREN, "Expected ')' after parenthesized expression");
            return expr_node;
        }
        case TOKEN_SWITCH:
            return parseSwitchExpression();
        case TOKEN_STRUCT:
            return parseStructDeclaration();
        case TOKEN_UNION:
            return parseUnionDeclaration();
        case TOKEN_ENUM:
            return parseEnumDeclaration();
        default:
            error("Expected a primary expression (literal, identifier, or parenthesized expression)");
            return NULL; // Unreachable
    }
}

/**
 * @brief Parses a postfix expression, including function calls and array accesses.
 *
 * This function handles expressions that are built upon primary expressions, such as
 * `my_func()`, `my_array[index]`, or chained calls like `get_array()[0]()`. It
 * parses the base expression and then loops to handle any number of trailing
 * postfix operations.
 *
 * Grammar:
 * `postfix_expr ::= primary_expr ( '(' (expr (',' expr)* ','?)? ')' | '[' expr ']' )*`
 *
 * @return A pointer to an `ASTNode` representing the parsed postfix expression.
 *         The node is allocated from the parser's arena.
 */
ASTNode* Parser::parsePostfixExpression() {
    ASTNode* expr = parsePrimaryExpr();

    while (true) {
        if (match(TOKEN_LPAREN)) {
            // Function Call
            ASTFunctionCallNode* call_node = (ASTFunctionCallNode*)arena_->alloc(sizeof(ASTFunctionCallNode));
            call_node->callee = expr;
            call_node->args = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            new (call_node->args) DynamicArray<ASTNode*>(*arena_);

            if (!match(TOKEN_RPAREN)) {
                do {
                    call_node->args->append(parseExpression());
                } while (match(TOKEN_COMMA) && peek().type != TOKEN_RPAREN);
                expect(TOKEN_RPAREN, "Expected ')' after function arguments");
            }

            ASTNode* new_expr_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
            new_expr_node->type = NODE_FUNCTION_CALL;
            new_expr_node->loc = expr->loc; // Use location of the callee
            new_expr_node->as.function_call = call_node;
            expr = new_expr_node;
        } else if (match(TOKEN_LBRACKET)) {
            // Array Access
            ASTArrayAccessNode* access_node = (ASTArrayAccessNode*)arena_->alloc(sizeof(ASTArrayAccessNode));
            access_node->array = expr;
            access_node->index = parseExpression();
            expect(TOKEN_RBRACKET, "Expected ']' after array index");

            ASTNode* new_expr_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
            new_expr_node->type = NODE_ARRAY_ACCESS;
            new_expr_node->loc = expr->loc; // Use location of the array expression
            new_expr_node->as.array_access = access_node;
            expr = new_expr_node;
        } else {
            break;
        }
    }

    return expr;
}

/**
 * @brief Parses a unary expression.
 *
 * This function handles prefix unary operators like `-`, `!`, `~`, and `&`. It
 * uses an iterative approach to handle chained operators (e.g., `!!x`) to avoid
 * deep recursion. It collects all unary operators, parses the postfix expression,
 * and then builds the nested unary expression nodes.
 *
 * Grammar:
 * `unary_expr ::= ('-' | '!' | '~' | '&')* postfix_expr`
 *
 * @return A pointer to an `ASTNode` representing the parsed unary expression.
 *         The node is allocated from the parser's arena.
 */
ASTNode* Parser::parseUnaryExpr() {
    DynamicArray<Token> operators(*arena_);

    while (peek().type == TOKEN_MINUS || peek().type == TOKEN_BANG || peek().type == TOKEN_TILDE || peek().type == TOKEN_AMPERSAND) {
        operators.append(advance());
    }

    ASTNode* expr = parsePostfixExpression();

    for (int i = operators.length() - 1; i >= 0; --i) {
        Token op_token = operators[i];

        ASTUnaryOpNode unary_op_node;
        unary_op_node.op = op_token.type;
        unary_op_node.operand = expr;

        ASTNode* new_expr_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        new_expr_node->type = NODE_UNARY_OP;
        new_expr_node->loc = op_token.location;
        new_expr_node->as.unary_op = unary_op_node;
        expr = new_expr_node;
    }

    return expr;
}

/**
 * @brief Gets the precedence level for a given binary operator token.
 * @param type The TokenType of the operator.
 * @return The operator's precedence level (higher value means higher precedence),
 *         or -1 if the token is not a binary operator.
 */
static int get_token_precedence(TokenType type) {
    switch (type) {
        // Arithmetic operators (highest precedence)
        case TOKEN_STAR:
        case TOKEN_SLASH:
        case TOKEN_PERCENT:
            return 10;
        case TOKEN_PLUS:
        case TOKEN_MINUS:
            return 9;

        // Bitwise shift operators
        case TOKEN_LARROW2:
        case TOKEN_RARROW2:
            return 8;

        // Bitwise logical operators
        case TOKEN_AMPERSAND:
            return 7;
        case TOKEN_CARET:
            return 6;
        case TOKEN_PIPE:
            return 5;

        // Comparison operators
        case TOKEN_EQUAL_EQUAL:
        case TOKEN_BANG_EQUAL:
        case TOKEN_LESS:
        case TOKEN_GREATER:
        case TOKEN_LESS_EQUAL:
        case TOKEN_GREATER_EQUAL:
            return 4;

        // Logical operators
        case TOKEN_AND:
            return 3;
        case TOKEN_OR:
            return 2;
        case TOKEN_ORELSE:
            return 1;

        default:
            return -1; // Not a binary operator
    }
}

/**
 * @brief Parses a binary expression using a Pratt parser algorithm.
 *
 * This function is the core of the expression parser. It handles operator
 * precedence and left-associativity. It takes a `min_precedence` to determine
 * whether to continue parsing a sequence of operators. For example, when parsing
 * `a + b * c`, after parsing `a + b`, it will see `*` which has a higher
 * precedence, so it will recursively call itself to parse `b * c` first.
 *
 * @param min_precedence The minimum operator precedence to bind to the left expression.
 * @return A pointer to the `ASTNode` representing the parsed expression, with
 *         correct precedence and associativity.
 */
ASTNode* Parser::parseBinaryExpr(int min_precedence) {
    ASTNode* left = parseUnaryExpr();

    while (true) {
        Token op_token = peek();
        int precedence = get_token_precedence(op_token.type);

        if (precedence < min_precedence) {
            break;
        }

        advance(); // Consume the operator

        if (is_at_end()) {
            error("Expected expression after binary operator");
        }

        // Handle associativity. Most operators are left-associative.
        // `orelse` is right-associative.
        int next_min_precedence = precedence + 1;
        if (op_token.type == TOKEN_ORELSE) {
            next_min_precedence = precedence;
        }
        ASTNode* right = parseBinaryExpr(next_min_precedence);

        ASTBinaryOpNode* binary_op = (ASTBinaryOpNode*)arena_->alloc(sizeof(ASTBinaryOpNode));
        binary_op->left = left;
        binary_op->right = right;
        binary_op->op = op_token.type;

        ASTNode* new_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        new_node->type = NODE_BINARY_OP;
        new_node->loc = op_token.location;
        new_node->as.binary_op = binary_op;
        left = new_node;
    }

    return left;
}

/**
 * @brief Parses an expression, correctly handling binary operator precedence.
 *
 * This is the main entry point for parsing expressions. It kicks off the Pratt
 * parser by calling `parseBinaryExpr` with a minimum precedence of 0.
 *
 * @return A pointer to the root `ASTNode` of the parsed expression tree.
 */
ASTNode* Parser::parseExpression() {
    return parseBinaryExpr(0);
}

/**
 * @brief Parses a switch expression.
 *
 * Grammar:
 * `switch '(' expr ')' '{' (prong (',' prong)* ','?)? '}'`
 * `prong ::= (expr (',' expr)* | 'else') '=>' expr`
 *
 * @return A pointer to an `ASTNode` representing the parsed switch expression.
 */
ASTNode* Parser::parseSwitchExpression() {
    Token switch_token = expect(TOKEN_SWITCH, "Expected 'switch' keyword");

    expect(TOKEN_LPAREN, "Missing opening parenthesis after switch");
    ASTNode* condition = parseExpression();
    expect(TOKEN_RPAREN, "Missing closing parenthesis around condition");

    expect(TOKEN_LBRACE, "Missing opening brace for prongs");

    ASTSwitchExprNode* switch_node = (ASTSwitchExprNode*)arena_->alloc(sizeof(ASTSwitchExprNode));
    switch_node->expression = condition;
    switch_node->prongs = (DynamicArray<ASTSwitchProngNode*>*)arena_->alloc(sizeof(DynamicArray<ASTSwitchProngNode*>));
    new (switch_node->prongs) DynamicArray<ASTSwitchProngNode*>(*arena_);

    bool has_else = false;

    if (peek().type == TOKEN_RBRACE) {
        advance(); // consume '}'
        error("Empty switch body {}");
    }

    do {
        ASTSwitchProngNode* prong_node = (ASTSwitchProngNode*)arena_->alloc(sizeof(ASTSwitchProngNode));
        prong_node->cases = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        new (prong_node->cases) DynamicArray<ASTNode*>(*arena_);
        prong_node->is_else = false;

        if (match(TOKEN_ELSE)) {
            if (has_else) {
                error("Duplicate else prong");
            }
            has_else = true;
            prong_node->is_else = true;
        } else {
            // Parse one or more case expressions
            do {
                prong_node->cases->append(parseExpression());
            } while (match(TOKEN_COMMA) && peek().type != TOKEN_FAT_ARROW);
        }

        expect(TOKEN_FAT_ARROW, "Missing => between cases and body");

        prong_node->body = parseExpression();
        if (prong_node->body == NULL) {
             error("Cases without corresponding body expression");
        }

        switch_node->prongs->append(prong_node);

    } while (match(TOKEN_COMMA) && peek().type != TOKEN_RBRACE);


    expect(TOKEN_RBRACE, "Expected '}' to close switch expression");

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_SWITCH_EXPR;
    node->loc = switch_token.location;
    node->as.switch_expr = switch_node;

    return node;
}

/**
 * @brief Parses an enum declaration type expression.
 *
 * This function handles anonymous enum literals. It parses an optional parenthesized
 * backing type, followed by a comma-separated list of members inside braces.
 * Each member can be a simple identifier or an identifier with an explicit
 * integer value.
 *
 * Grammar:
 * `enum ('(' type ')')? '{' (member (',' member)* ','?)? '}'`
 * `member ::= IDENTIFIER ('=' expr)?`
 *
 * @return A pointer to an `ASTNode` representing the parsed enum declaration.
 *         The node is allocated from the parser's arena.
 */
ASTNode* Parser::parseEnumDeclaration() {
    Token enum_token = expect(TOKEN_ENUM, "Expected 'enum' keyword");
    ASTNode* backing_type = NULL;

    // Parse optional backing type
    if (match(TOKEN_LPAREN)) {
        backing_type = parseType();
        expect(TOKEN_RPAREN, "Expected ')' after enum backing type");
    }

    expect(TOKEN_LBRACE, "Expected '{' to begin enum declaration");

    ASTEnumDeclNode* enum_decl = (ASTEnumDeclNode*)arena_->alloc(sizeof(ASTEnumDeclNode));
    enum_decl->backing_type = backing_type;
    enum_decl->fields = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    new (enum_decl->fields) DynamicArray<ASTNode*>(*arena_);

    // Handle members
    while (peek().type != TOKEN_RBRACE && !is_at_end()) {
        Token name_token = expect(TOKEN_IDENTIFIER, "Expected member name in enum declaration");
        ASTNode* initializer = NULL;

        if (match(TOKEN_EQUAL)) {
            initializer = parseExpression();
        }

        ASTVarDeclNode* field_data = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
        field_data->name = name_token.value.identifier;
        field_data->type = NULL; // Enums members don't have a type annotation
        field_data->initializer = initializer;
        field_data->is_const = true; // Enum members are constants
        field_data->is_mut = false;

        ASTNode* field_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        field_node->type = NODE_VAR_DECL;
        field_node->loc = name_token.location;
        field_node->as.var_decl = field_data;

        enum_decl->fields->append(field_node);

        // If the next token is not a closing brace, it must be a comma.
        if (peek().type != TOKEN_RBRACE) {
            expect(TOKEN_COMMA, "Expected ',' or '}' after enum member");
        }
    }

    expect(TOKEN_RBRACE, "Expected '}' to end enum declaration");

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_ENUM_DECL;
    node->loc = enum_token.location;
    node->as.enum_decl = enum_decl;

    return node;
}

/**
 * @brief Parses a union declaration type expression.
 *
 * This function handles anonymous union literals, which can be used anywhere a
 * type is expected. It parses a comma-separated list of fields, where each
 * field consists of an identifier, a colon, and a type expression. It correctly
 * handles empty unions and optional trailing commas.
 *
 * Grammar:
 * `union '{' (field (',' field)* ','?)? '}'`
 * `field ::= IDENTIFIER ':' type`
 *
 * @return A pointer to an `ASTNode` representing the parsed union declaration.
 *         The node is allocated from the parser's arena.
 */
ASTNode* Parser::parseUnionDeclaration() {
    Token union_token = expect(TOKEN_UNION, "Expected 'union' keyword");
    expect(TOKEN_LBRACE, "Expected '{' to begin union declaration");

    ASTUnionDeclNode* union_decl = (ASTUnionDeclNode*)arena_->alloc(sizeof(ASTUnionDeclNode));
    union_decl->fields = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    new (union_decl->fields) DynamicArray<ASTNode*>(*arena_);

    // Handle fields
    while (peek().type != TOKEN_RBRACE && !is_at_end()) {
        Token name_token = expect(TOKEN_IDENTIFIER, "Expected field name in union declaration");
        expect(TOKEN_COLON, "Expected ':' after field name");
        ASTNode* type_node = parseType();

        ASTStructFieldNode* field_data = (ASTStructFieldNode*)arena_->alloc(sizeof(ASTStructFieldNode));
        field_data->name = name_token.value.identifier;
        field_data->type = type_node;

        ASTNode* field_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        field_node->type = NODE_STRUCT_FIELD;
        field_node->loc = name_token.location;
        field_node->as.struct_field = field_data;

        union_decl->fields->append(field_node);

        // If the next token is not a closing brace, it must be a comma.
        if (peek().type != TOKEN_RBRACE) {
            expect(TOKEN_COMMA, "Expected ',' or '}' after union field");
        }
    }

    expect(TOKEN_RBRACE, "Expected '}' to end union declaration");

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_UNION_DECL;
    node->loc = union_token.location;
    node->as.union_decl = union_decl;

    return node;
}


/**
 * @brief Parses a struct declaration type expression.
 *
 * This function handles anonymous struct literals, which can be used anywhere a
 * type is expected. It parses a comma-separated list of fields, where each
 * field consists of an identifier, a colon, and a type expression. It correctly
 * handles empty structs and optional trailing commas.
 *
 * Grammar:
 * `struct '{' (field (',' field)* ','?)? '}'`
 * `field ::= IDENTIFIER ':' type`
 *
 * @return A pointer to an `ASTNode` representing the parsed struct declaration.
 *         The node is allocated from the parser's arena.
 */
ASTNode* Parser::parseStructDeclaration() {
    Token struct_token = expect(TOKEN_STRUCT, "Expected 'struct' keyword");
    expect(TOKEN_LBRACE, "Expected '{' to begin struct declaration");

    ASTStructDeclNode* struct_decl = (ASTStructDeclNode*)arena_->alloc(sizeof(ASTStructDeclNode));
    struct_decl->fields = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    new (struct_decl->fields) DynamicArray<ASTNode*>(*arena_);

    // Handle fields
    while (peek().type != TOKEN_RBRACE && !is_at_end()) {
        Token name_token = expect(TOKEN_IDENTIFIER, "Expected field name in struct declaration");
        expect(TOKEN_COLON, "Expected ':' after field name");
        ASTNode* type_node = parseType();

        ASTStructFieldNode* field_data = (ASTStructFieldNode*)arena_->alloc(sizeof(ASTStructFieldNode));
        field_data->name = name_token.value.identifier;
        field_data->type = type_node;

        ASTNode* field_node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
        field_node->type = NODE_STRUCT_FIELD;
        field_node->loc = name_token.location;
        field_node->as.struct_field = field_data;

        struct_decl->fields->append(field_node);

        // If the next token is not a closing brace, it must be a comma.
        if (peek().type != TOKEN_RBRACE) {
            expect(TOKEN_COMMA, "Expected ',' or '}' after struct field");
        }
    }

    expect(TOKEN_RBRACE, "Expected '}' to end struct declaration");

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_STRUCT_DECL;
    node->loc = struct_token.location;
    node->as.struct_decl = struct_decl;

    return node;
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
 * @brief Parses a for statement.
 *        Grammar: `'for' '(' expr ')' '|' IDENT (',' IDENT)? '|' block_statement`
 * @return A pointer to the ASTNode representing the for statement.
 */
ASTNode* Parser::parseForStatement() {
    Token for_token = expect(TOKEN_FOR, "Expected 'for' keyword");
    expect(TOKEN_LPAREN, "Expected '(' after 'for'");
    ASTNode* iterable_expr = parseExpression();
    expect(TOKEN_RPAREN, "Expected ')' after for iterable expression");

    expect(TOKEN_PIPE, "Expected '|' to start for loop capture list");

    Token item_token = expect(TOKEN_IDENTIFIER, "Expected item name in for loop capture list");
    const char* item_name = item_token.value.identifier;
    const char* index_name = NULL;

    if (match(TOKEN_COMMA)) {
        Token index_token = expect(TOKEN_IDENTIFIER, "Expected index name after comma in for loop capture list");
        index_name = index_token.value.identifier;
    }

    expect(TOKEN_PIPE, "Expected '|' to end for loop capture list");

    ASTNode* body = parseBlockStatement();

    ASTForStmtNode* for_stmt_node = (ASTForStmtNode*)arena_->alloc(sizeof(ASTForStmtNode));
    for_stmt_node->iterable_expr = iterable_expr;
    for_stmt_node->item_name = item_name;
    for_stmt_node->index_name = index_name;
    for_stmt_node->body = body;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_FOR_STMT;
    node->loc = for_token.location;
    node->as.for_stmt = for_stmt_node;

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
        case TOKEN_RETURN:
            return parseReturnStatement();
        case TOKEN_IF:
            return parseIfStatement();
        case TOKEN_FOR:
            return parseForStatement();
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

/**
 * @brief Parses a return statement.
 *        Grammar: `'return' (expr)? ';'`
 * @return A pointer to the ASTNode representing the return statement.
 */
ASTNode* Parser::parseReturnStatement() {
    Token return_token = expect(TOKEN_RETURN, "Expected 'return' keyword");

    ASTNode* expression = NULL;
    if (peek().type != TOKEN_SEMICOLON) {
        expression = parseExpression();
    }

    expect(TOKEN_SEMICOLON, "Expected ';' after return statement");

    ASTReturnStmtNode return_stmt;
    return_stmt.expression = expression;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    node->type = NODE_RETURN_STMT;
    node->loc = return_token.location;
    node->as.return_stmt = return_stmt;

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
