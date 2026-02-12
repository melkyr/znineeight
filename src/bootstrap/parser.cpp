#include "parser.hpp"
#include "error_set_catalogue.hpp"
#include "generic_catalogue.hpp"
#include "ast.hpp"
#include "type_system.hpp"
#include "platform.hpp"
#include "utils.hpp"
#include <cstdlib>   // For abort()
#include <new>       // For placement new

/**
 * @brief Constructs a new Parser instance.
 */
Parser::Parser(const Token* tokens, size_t count, ArenaAllocator* arena, SymbolTable* symbol_table, ErrorSetCatalogue* catalogue, GenericCatalogue* generic_catalogue, TypeInterner* type_interner, const char* module_name)
    : tokens_(tokens),
      token_count_(count),
      current_index_(0),
      arena_(arena),
      symbol_table_(symbol_table),
      catalogue_(catalogue),
      generic_catalogue_(generic_catalogue),
      type_interner_(type_interner),
      module_name_(module_name),
      recursion_depth_(0)
{
    assert(arena_ != NULL && "ArenaAllocator cannot be null");
    assert(symbol_table_ != NULL && "SymbolTable cannot be null");
    // Initialize the EOF token.
    eof_token_.type = TOKEN_EOF;
    eof_token_.value.identifier = NULL;
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
    plat_print_debug("Parser Error: ");
    plat_print_debug(msg);
    plat_print_debug(" at token ");
    char buf[64];
    Token t = peek();
    simple_itoa((long)t.type, buf, sizeof(buf));
    plat_print_debug(buf);
    if (t.type == TOKEN_IDENTIFIER || t.type == TOKEN_STRING_LITERAL) {
        plat_print_debug(" (");
        plat_print_debug(t.value.identifier);
        plat_print_debug(")");
    }
    plat_print_debug("\n");

    abort();
}

ASTNode* Parser::createNode(NodeType type) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
#ifdef MEASURE_MEMORY
    MemoryTracker::ast_nodes++;
#endif
    if (!node) {
        error("Out of memory");
    }
    node->type = type;
    node->resolved_type = NULL;
    node->module = module_name_;
    node->loc = peek().location;
    return node;
}

ASTNode* Parser::createNodeAt(NodeType type, SourceLocation loc) {
    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
#ifdef MEASURE_MEMORY
    MemoryTracker::ast_nodes++;
#endif
    if (!node) {
        error("Out of memory");
    }
    node->type = type;
    node->resolved_type = NULL;
    node->module = module_name_;
    node->loc = loc;
    return node;
}

/**
 * @brief Parses a comptime block.
 * @return A pointer to the ASTNode representing the comptime block.
 * @grammar `comptime '{' expression '}'`
 */
ASTNode* Parser::parseComptimeBlock() {
    Token comptime_token = expect(TOKEN_COMPTIME, "Expected 'comptime' keyword.");

    expect(TOKEN_LBRACE, "Expected '{' after 'comptime'.");

    ASTNode* expr = parseExpression();
    if (expr == NULL) {
        error("Expected an expression inside comptime block.");
    }

    expect(TOKEN_RBRACE, "Expected '}' after comptime block expression.");

    // Build the AST node
    ASTComptimeBlockNode comptime_block;
    comptime_block.expression = expr;

    ASTNode* node = createNodeAt(NODE_COMPTIME_BLOCK, comptime_token.location);
    node->as.comptime_block = comptime_block;

    return node;
}

const Token& Parser::peekNext() const {
    if (current_index_ + 1 >= token_count_) {
        return eof_token_;
    }
    return tokens_[current_index_ + 1];
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

    switch (token.type) {
        case TOKEN_NULL: {
            ASTNode* node = createNode(NODE_NULL_LITERAL);
            advance();
            return node;
        }
        case TOKEN_TRUE: {
            ASTNode* node = createNode(NODE_BOOL_LITERAL);
            advance();
            node->as.bool_literal.value = true;
            return node;
        }
        case TOKEN_FALSE: {
            ASTNode* node = createNode(NODE_BOOL_LITERAL);
            advance();
            node->as.bool_literal.value = false;
            return node;
        }
        case TOKEN_INTEGER_LITERAL: {
            ASTNode* node = createNode(NODE_INTEGER_LITERAL);
            advance();
            node->as.integer_literal.value = token.value.integer_literal.value;
            node->as.integer_literal.is_unsigned = token.value.integer_literal.is_unsigned;
            node->as.integer_literal.is_long = token.value.integer_literal.is_long;
            node->as.integer_literal.resolved_type = NULL;
            return node;
        }
        case TOKEN_FLOAT_LITERAL: {
            ASTNode* node = createNode(NODE_FLOAT_LITERAL);
            advance();
            node->as.float_literal.value = token.value.floating_point;
            node->as.float_literal.resolved_type = NULL;
            return node;
        }
        case TOKEN_CHAR_LITERAL: {
            ASTNode* node = createNode(NODE_CHAR_LITERAL);
            advance();
            node->as.char_literal.value = token.value.character;
            return node;
        }
        case TOKEN_STRING_LITERAL: {
            ASTNode* node = createNode(NODE_STRING_LITERAL);
            advance();
            node->as.string_literal.value = token.value.identifier;
            return node;
        }
        case TOKEN_IDENTIFIER: {
            ASTNode* node = createNode(NODE_IDENTIFIER);
            advance();
            node->as.identifier.name = token.value.identifier;
            return node;
        }
        case TOKEN_LPAREN: {
            advance(); // consume '('
            ASTNode* inner_expr = parseExpression();
            expect(TOKEN_RPAREN, "Expected ')' after parenthesized expression");
            ASTNode* node = createNode(NODE_PAREN_EXPR);
            node->as.paren_expr.expr = inner_expr;
            return node;
        }
        case TOKEN_LBRACE:
            return parseBlockStatement();
        case TOKEN_SWITCH:
            return parseSwitchExpression();
        case TOKEN_STRUCT:
            return parseStructDeclaration();
        case TOKEN_UNION:
            return parseUnionDeclaration();
        case TOKEN_ENUM:
            return parseEnumDeclaration();
        case TOKEN_ERROR_SET:
            return parseErrorSetDefinition();
        case TOKEN_AT_IMPORT:
            return parseImport();
        case TOKEN_AT_SIZEOF:
            return parseBuiltinCall("@sizeOf", advance().location);
        case TOKEN_AT_ALIGNOF:
            return parseBuiltinCall("@alignOf", advance().location);
        case TOKEN_AT_PTRCAST:
            return parsePtrCastExpr();
        case TOKEN_AT_INTCAST:
            return parseNumericCastExpr(NODE_INT_CAST);
        case TOKEN_AT_FLOATCAST:
            return parseNumericCastExpr(NODE_FLOAT_CAST);
        case TOKEN_AT_OFFSETOF:
            return parseOffsetOfExpr();
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
    recursion_depth_++;
    if (recursion_depth_ > MAX_PARSER_RECURSION_DEPTH) {
        error("Expression too complex, recursion limit reached");
    }

    ASTNode* expr = parsePrimaryExpr();

    while (true) {
        if (match(TOKEN_LPAREN)) {
            // Function Call
            ASTFunctionCallNode* call_node = (ASTFunctionCallNode*)arena_->alloc(sizeof(ASTFunctionCallNode));
            if (!call_node) {
                error("Out of memory");
            }
            call_node->callee = expr;
            call_node->args = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
            if (!call_node->args) {
                error("Out of memory");
            }
            new (call_node->args) DynamicArray<ASTNode*>(*arena_);

            if (!match(TOKEN_RPAREN)) {
                do {
                    call_node->args->append(parseExpression());
                } while (match(TOKEN_COMMA) && peek().type != TOKEN_RPAREN);
                expect(TOKEN_RPAREN, "Expected ')' after function arguments");
            }

            ASTNode* new_expr_node = createNodeAt(NODE_FUNCTION_CALL, expr->loc);
            new_expr_node->as.function_call = call_node;
            expr = new_expr_node;
        } else if (match(TOKEN_LBRACKET)) {
            // Check if this is a slice expression [start..end], [..end], [start..], or [..]
            if (peek().type == TOKEN_RANGE ||
                (peek().type != TOKEN_RBRACKET && peekNext().type == TOKEN_RANGE)) {

                ASTArraySliceNode* slice_node = (ASTArraySliceNode*)arena_->alloc(sizeof(ASTArraySliceNode));
                if (!slice_node) {
                    error("Out of memory");
                }
                slice_node->array = expr;

                // Parse start index (if present)
                if (peek().type != TOKEN_RANGE) {
                    slice_node->start = parseExpression();
                    expect(TOKEN_RANGE, "Expected '..' after start index in slice expression");
                } else {
                    slice_node->start = NULL; // Implicit start (array[..end])
                    advance(); // Consume the '..'
                }

                // Parse end index (if present)
                if (peek().type != TOKEN_RBRACKET) {
                    slice_node->end = parseExpression();
                } else {
                    slice_node->end = NULL; // Implicit end (array[start..] or array[..])
                }

                expect(TOKEN_RBRACKET, "Expected ']' after slice expression");

                ASTNode* new_expr_node = createNodeAt(NODE_ARRAY_SLICE, expr->loc);
                new_expr_node->as.array_slice = slice_node;
                expr = new_expr_node;
            }
            else {
                // Regular array access [index]
                ASTArrayAccessNode* access_node = (ASTArrayAccessNode*)arena_->alloc(sizeof(ASTArrayAccessNode));
                if (!access_node) {
                    error("Out of memory");
                }
                access_node->array = expr;
                access_node->index = parseExpression();
                expect(TOKEN_RBRACKET, "Expected ']' after array index");

                ASTNode* new_expr_node = createNodeAt(NODE_ARRAY_ACCESS, expr->loc);
                new_expr_node->as.array_access = access_node;
                expr = new_expr_node;
            }
        } else if (match(TOKEN_DOT)) {
            // Member Access: s.field
            Token name_token = expect(TOKEN_IDENTIFIER, "Expected field name after '.'");

            ASTMemberAccessNode* member_node = (ASTMemberAccessNode*)arena_->alloc(sizeof(ASTMemberAccessNode));
            if (!member_node) error("Out of memory");
            member_node->base = expr;
            member_node->field_name = name_token.value.identifier;

            ASTNode* new_expr_node = createNode(NODE_MEMBER_ACCESS);
            new_expr_node->loc = name_token.location;
            new_expr_node->as.member_access = member_node;
            expr = new_expr_node;
        } else if (peek().type == TOKEN_LBRACE && (expr->type == NODE_IDENTIFIER || expr->type == NODE_TYPE_NAME)) {
            // Struct Initializer: Type { .field = value }
            expr = parseStructInitializer(expr);
        } else if (match(TOKEN_DOT_ASTERISK)) {
            // Zig-style dereference: p.*
            ASTNode* new_expr_node = createNode(NODE_UNARY_OP);
            new_expr_node->as.unary_op.op = TOKEN_DOT_ASTERISK;
            new_expr_node->as.unary_op.operand = expr;
            expr = new_expr_node;
        } else if (match(TOKEN_PLUS2) || match(TOKEN_MINUS2)) {
            // Postfix increment/decrement: x++, x--
            TokenType op = tokens_[current_index_ - 1].type;
            ASTUnaryOpNode unary_op_node;
            unary_op_node.op = op;
            unary_op_node.operand = expr;

            ASTNode* new_expr_node = createNodeAt(NODE_UNARY_OP, tokens_[current_index_ - 1].location);
            new_expr_node->as.unary_op = unary_op_node;
            expr = new_expr_node;
        } else {
            break;
        }
    }

    recursion_depth_--;
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
    recursion_depth_++;
    if (recursion_depth_ > MAX_PARSER_RECURSION_DEPTH) {
        error("Expression too complex, recursion limit reached");
    }

    if (peek().type == TOKEN_TRY) {
        Token try_token = advance();
        ASTNode* expression = parseUnaryExpr(); // Recursively call to handle chained operators e.g. try !foo()

        ASTTryExprNode try_expr_node;
        try_expr_node.expression = expression;

        ASTNode* node = createNodeAt(NODE_TRY_EXPR, try_token.location);
        node->as.try_expr = try_expr_node;
        recursion_depth_--;
        return node;
    }
    DynamicArray<Token> operators(*arena_);

    while (peek().type == TOKEN_MINUS || peek().type == TOKEN_BANG || peek().type == TOKEN_TILDE ||
           peek().type == TOKEN_AMPERSAND || peek().type == TOKEN_PLUS2 || peek().type == TOKEN_MINUS2) {
        operators.append(advance());
    }

    ASTNode* expr = parsePostfixExpression();

    for (int i = operators.length() - 1; i >= 0; --i) {
        Token op_token = operators[i];

        ASTUnaryOpNode unary_op_node;
        unary_op_node.op = op_token.type;
        unary_op_node.operand = expr;

        ASTNode* new_expr_node = createNodeAt(NODE_UNARY_OP, op_token.location);
        new_expr_node->as.unary_op = unary_op_node;
        expr = new_expr_node;
    }

    recursion_depth_--;
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

        // Error handling and optional unwrapping (lowest precedence)
        case TOKEN_ORELSE:
        case TOKEN_CATCH:
        case TOKEN_PIPE_PIPE:
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
 * @brief Parses binary expressions with precedence greater than 1.
 *
 * This function is a helper for the main `parseExpression` function. It uses a
 * standard Pratt parsing (recursive descent) approach to handle all left-associative
 * operators with a precedence level of 2 or higher (i.e., everything except
 * `orelse` and `catch`).
 *
 * @param min_precedence The minimum operator precedence to bind to the left expression.
 * @return A pointer to the `ASTNode` representing the parsed expression, with
 *         correct precedence and associativity.
 */
ASTNode* Parser::parsePrecedenceExpr(int min_precedence) {
    recursion_depth_++;
    if (recursion_depth_ > MAX_PARSER_RECURSION_DEPTH) {
        error("Expression too complex, recursion limit reached");
    }

    ASTNode* left = parseUnaryExpr();

    while (true) {
        Token op_token = peek();
        int precedence = get_token_precedence(op_token.type);

        // This function now only handles left-associative operators with precedence > 1
        if (precedence < min_precedence) {
            break;
        }

        advance(); // Consume the operator

        if (op_token.type == TOKEN_CATCH) {
            const char* payload_name = NULL;
            if (match(TOKEN_PIPE)) {
                Token id_token = expect(TOKEN_IDENTIFIER, "Expected identifier for error capture payload");
                payload_name = id_token.value.identifier;
                expect(TOKEN_PIPE, "Expected closing '|' after error capture payload");
            }

            ASTNode* else_expr = parsePrecedenceExpr(precedence + 1);

            ASTCatchExprNode* catch_node = (ASTCatchExprNode*)arena_->alloc(sizeof(ASTCatchExprNode));
             if (!catch_node) {
                error("Out of memory");
            }
            catch_node->payload = left;
            catch_node->error_name = payload_name;
            catch_node->else_expr = else_expr;

            ASTNode* new_node = createNodeAt(NODE_CATCH_EXPR, op_token.location);
            new_node->as.catch_expr = catch_node;
            left = new_node;
        } else if (op_token.type == TOKEN_ORELSE) {
            ASTNode* else_expr = parsePrecedenceExpr(precedence + 1);

            ASTOrelseExprNode* orelse_node = (ASTOrelseExprNode*)arena_->alloc(sizeof(ASTOrelseExprNode));
            if (!orelse_node) {
                error("Out of memory");
            }
            orelse_node->payload = left;
            orelse_node->else_expr = else_expr;

            ASTNode* new_node = createNodeAt(NODE_ORELSE_EXPR, op_token.location);
            new_node->as.orelse_expr = orelse_node;
            left = new_node;
        } else if (op_token.type == TOKEN_PIPE_PIPE) {
            ASTNode* right = parsePrecedenceExpr(precedence + 1);

            ASTErrorSetMergeNode* merge_data = (ASTErrorSetMergeNode*)arena_->alloc(sizeof(ASTErrorSetMergeNode));
            if (!merge_data) {
                error("Out of memory");
            }
            merge_data->left = left;
            merge_data->right = right;

            ASTNode* new_node = createNodeAt(NODE_ERROR_SET_MERGE, op_token.location);
            new_node->as.error_set_merge = merge_data;
            left = new_node;
        } else {
            ASTNode* right = parsePrecedenceExpr(precedence + 1);

            ASTBinaryOpNode* binary_op = (ASTBinaryOpNode*)arena_->alloc(sizeof(ASTBinaryOpNode));
            if (!binary_op) {
                error("Out of memory");
            }
            binary_op->left = left;
            binary_op->right = right;
            binary_op->op = op_token.type;

            ASTNode* new_node = createNodeAt(NODE_BINARY_OP, op_token.location);
            new_node->as.binary_op = binary_op;
            left = new_node;
        }
    }

    recursion_depth_--;
    return left;
}

/**
 * @brief Parses an expression, handling right-associative operators iteratively.
 *
 * This function is the main entry point for expression parsing. It handles the
 * lowest precedence, right-associative operators (`orelse`, `catch`) with an
 * iterative approach to prevent deep recursion on long chains. It uses a helper
 * function, `parsePrecedenceExpr`, to handle all higher-precedence, left-associative
 * operators recursively.
 *
 * @return A pointer to the root `ASTNode` of the parsed expression tree.
 */
ASTNode* Parser::parseOrelseCatchExpression() {
    return parsePrecedenceExpr(1); // Start with orelse/catch precedence
}

/**
 * @brief Parses an assignment expression.
 * @return A pointer to the ASTNode representing the assignment.
 */
ASTNode* Parser::parseAssignmentExpression() {
    ASTNode* left = parseOrelseCatchExpression();

    if (match(TOKEN_EQUAL)) {
        ASTNode* right = parseAssignmentExpression();

        ASTAssignmentNode* assign_node = (ASTAssignmentNode*)arena_->alloc(sizeof(ASTAssignmentNode));
        if (!assign_node) {
            error("Out of memory");
        }
        assign_node->lvalue = left;
        assign_node->rvalue = right;

        ASTNode* node = createNode(NODE_ASSIGNMENT);
        node->as.assignment = assign_node;
        return node;
    }

    TokenType compound_ops[] = {
        TOKEN_PLUS_EQUAL, TOKEN_MINUS_EQUAL, TOKEN_STAR_EQUAL,
        TOKEN_SLASH_EQUAL, TOKEN_PERCENT_EQUAL, TOKEN_AMPERSAND_EQUAL,
        TOKEN_PIPE_EQUAL, TOKEN_CARET_EQUAL, TOKEN_LARROW2_EQUAL,
        TOKEN_RARROW2_EQUAL
    };

    for (size_t i = 0; i < sizeof(compound_ops) / sizeof(compound_ops[0]); ++i) {
        if (match(compound_ops[i])) {
            TokenType op = compound_ops[i];
            ASTNode* right = parseAssignmentExpression();

            ASTCompoundAssignmentNode* comp_node = (ASTCompoundAssignmentNode*)arena_->alloc(sizeof(ASTCompoundAssignmentNode));
            if (!comp_node) {
                error("Out of memory");
            }
            comp_node->lvalue = left;
            comp_node->rvalue = right;
            comp_node->op = op;

            ASTNode* node = createNode(NODE_COMPOUND_ASSIGNMENT);
            node->as.compound_assignment = comp_node;
            return node;
        }
    }

    return left;
}

ASTNode* Parser::parseExpression() {
    return parseAssignmentExpression();
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
    if (!switch_node) {
        error("Out of memory");
    }
    switch_node->expression = condition;
    switch_node->prongs = (DynamicArray<ASTSwitchProngNode*>*)arena_->alloc(sizeof(DynamicArray<ASTSwitchProngNode*>));
    if (!switch_node->prongs) {
        error("Out of memory");
    }
    new (switch_node->prongs) DynamicArray<ASTSwitchProngNode*>(*arena_);

    bool has_else = false;

    if (peek().type == TOKEN_RBRACE) {
        advance(); // consume '}'
        error("Empty switch body {}");
    }

    do {
        ASTSwitchProngNode* prong_node = (ASTSwitchProngNode*)arena_->alloc(sizeof(ASTSwitchProngNode));
        if (!prong_node) {
            error("Out of memory");
        }
        prong_node->cases = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
        if (!prong_node->cases) {
            error("Out of memory");
        }
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

    ASTNode* node = createNodeAt(NODE_SWITCH_EXPR, switch_token.location);
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
ASTNode* Parser::parseStructInitializer(ASTNode* type_expr) {
    Token lbrace = expect(TOKEN_LBRACE, "Expected '{' to start struct initializer");

    ASTStructInitializerNode* init_data = (ASTStructInitializerNode*)arena_->alloc(sizeof(ASTStructInitializerNode));
    if (!init_data) error("Out of memory");
    init_data->type_expr = type_expr;
    init_data->fields = (DynamicArray<ASTNamedInitializer*>*)arena_->alloc(sizeof(DynamicArray<ASTNamedInitializer*>));
    if (!init_data->fields) error("Out of memory");
    new (init_data->fields) DynamicArray<ASTNamedInitializer*>(*arena_);

    while (peek().type != TOKEN_RBRACE && !is_at_end()) {
        expect(TOKEN_DOT, "Expected '.' before field name in struct initializer");
        Token field_name = expect(TOKEN_IDENTIFIER, "Expected field name in struct initializer");
        expect(TOKEN_EQUAL, "Expected '=' after field name in struct initializer");
        ASTNode* value = parseExpression();

        ASTNamedInitializer* named_init = (ASTNamedInitializer*)arena_->alloc(sizeof(ASTNamedInitializer));
        if (!named_init) error("Out of memory");
        named_init->field_name = field_name.value.identifier;
        named_init->value = value;
        named_init->loc = field_name.location;

        init_data->fields->append(named_init);

        if (!match(TOKEN_COMMA)) break;
    }

    expect(TOKEN_RBRACE, "Expected '}' after struct initializer");

    ASTNode* node = createNode(NODE_STRUCT_INITIALIZER);
    node->loc = lbrace.location;
    node->as.struct_initializer = init_data;
    return node;
}

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
    if (!enum_decl) {
        error("Out of memory");
    }
    enum_decl->backing_type = backing_type;
    enum_decl->fields = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!enum_decl->fields) {
        error("Out of memory");
    }
    new (enum_decl->fields) DynamicArray<ASTNode*>(*arena_);

    // Handle members
    while (peek().type != TOKEN_RBRACE && !is_at_end()) {
        Token name_token = expect(TOKEN_IDENTIFIER, "Expected member name in enum declaration");
        ASTNode* initializer = NULL;

        if (match(TOKEN_EQUAL)) {
            initializer = parseExpression();
        }

        ASTVarDeclNode* field_data = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
        if (!field_data) {
            error("Out of memory");
        }
        field_data->name = name_token.value.identifier;
        field_data->name_loc = name_token.location;
        field_data->type = NULL; // Enums members don't have a type annotation
        field_data->initializer = initializer;
        field_data->is_const = true; // Enum members are constants
        field_data->is_mut = false;

        ASTNode* field_node = createNode(NODE_VAR_DECL);
        field_node->loc = name_token.location;
        field_node->as.var_decl = field_data;

        enum_decl->fields->append(field_node);

        // If the next token is not a closing brace, it must be a comma.
        if (peek().type != TOKEN_RBRACE) {
            expect(TOKEN_COMMA, "Expected ',' or '}' after enum member");
        }
    }

    expect(TOKEN_RBRACE, "Expected '}' to end enum declaration");

    ASTNode* node = createNodeAt(NODE_ENUM_DECL, enum_token.location);
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
    if (!union_decl) {
        error("Out of memory");
    }
    union_decl->fields = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!union_decl->fields) {
        error("Out of memory");
    }
    new (union_decl->fields) DynamicArray<ASTNode*>(*arena_);

    // Handle fields
    while (peek().type != TOKEN_RBRACE && !is_at_end()) {
        if (peek().type == TOKEN_FN || peek().type == TOKEN_PUB) {
            error("Methods are not supported in union declarations in bootstrap compiler");
        }

        Token name_token = expect(TOKEN_IDENTIFIER, "Expected field name in union declaration");
        expect(TOKEN_COLON, "Expected ':' after field name");
        ASTNode* type_node = parseType();

        if (peek().type == TOKEN_EQUAL) {
            error("Default field values are not supported in bootstrap compiler");
        }

        ASTStructFieldNode* field_data = (ASTStructFieldNode*)arena_->alloc(sizeof(ASTStructFieldNode));
        if (!field_data) {
            error("Out of memory");
        }
        field_data->name = name_token.value.identifier;
        field_data->name_loc = name_token.location;
        field_data->type = type_node;

        ASTNode* field_node = createNode(NODE_STRUCT_FIELD);
        field_node->loc = name_token.location;
        field_node->as.struct_field = field_data;

        union_decl->fields->append(field_node);

        // If the next token is not a closing brace, it must be a comma.
        if (peek().type != TOKEN_RBRACE) {
            expect(TOKEN_COMMA, "Expected ',' or '}' after union field");
        }
    }

    expect(TOKEN_RBRACE, "Expected '}' to end union declaration");

    ASTNode* node = createNodeAt(NODE_UNION_DECL, union_token.location);
    node->as.union_decl = union_decl;

    return node;
}

/**
 * @brief Parses an errdefer statement.
 *        Grammar: `'errdefer' block_statement`
 * @return A pointer to the ASTNode representing the errdefer statement.
 */
ASTNode* Parser::parseErrDeferStatement() {
    Token errdefer_token = expect(TOKEN_ERRDEFER, "Expected 'errdefer' keyword");

    // The statement following 'errdefer' must be a block statement.
    ASTNode* statement = parseBlockStatement();

    ASTErrDeferStmtNode errdefer_stmt;
    errdefer_stmt.statement = statement;

    ASTNode* node = createNodeAt(NODE_ERRDEFER_STMT, errdefer_token.location);
    node->as.errdefer_stmt = errdefer_stmt;

    return node;
}

ASTNode* Parser::parse() {
    Token start_token = peek();
    DynamicArray<ASTNode*>* statements = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!statements) {
        error("Out of memory");
    }
    new (statements) DynamicArray<ASTNode*>(*arena_);

    while (!is_at_end()) {
        statements->append(parseTopLevelItem());
    }

    ASTNode* block_node = createNode(NODE_BLOCK_STMT);
    block_node->loc = start_token.location;
    block_node->as.block_stmt.statements = statements;

    return block_node;
}

/**
 * @brief Parses an error set definition (e.g., `error { A, B }`).
 * @return A pointer to an `ASTNode` representing the error set definition.
 */
ASTNode* Parser::parseErrorSetDefinition() {
    Token error_token = expect(TOKEN_ERROR_SET, "Expected 'error'");

    DynamicArray<const char*>* tags = NULL;

    if (match(TOKEN_LBRACE)) {
        void* tags_mem = arena_->alloc(sizeof(DynamicArray<const char*>));
        if (!tags_mem) error("Out of memory");
        tags = new (tags_mem) DynamicArray<const char*>(*arena_);

        while (!is_at_end() && peek().type != TOKEN_RBRACE) {
            Token tag_token = expect(TOKEN_IDENTIFIER, "Expected error tag identifier");
            tags->append(tag_token.value.identifier);

            if (!match(TOKEN_COMMA)) break;
        }
        expect(TOKEN_RBRACE, "Expected '}' after error tags");
    }

    // Add to catalogue. Name is initially NULL; might be updated by caller if assigned to a const.
    catalogue_->addErrorSet(NULL, tags, error_token.location);

    ASTErrorSetDefinitionNode* es_node = (ASTErrorSetDefinitionNode*)arena_->alloc(sizeof(ASTErrorSetDefinitionNode));
    if (!es_node) error("Out of memory");
    es_node->name = NULL;
    es_node->tags = tags;

    ASTNode* node = createNode(NODE_ERROR_SET_DEFINITION);
    node->loc = error_token.location;
    node->as.error_set_decl = es_node;

    return node;
}

/**
 * @brief Parses an @import statement.
 * @return A pointer to an `ASTNode` representing the import.
 */
ASTNode* Parser::parseImport() {
    Token import_token = expect(TOKEN_AT_IMPORT, "Expected '@import'");
    expect(TOKEN_LPAREN, "Expected '(' after '@import'");
    Token module_token = expect(TOKEN_STRING_LITERAL, "Expected module name string after '@import('");
    expect(TOKEN_RPAREN, "Expected ')' after module name");

    // Parse as a function call to "@import"
    ASTNode* callee = createNodeAt(NODE_IDENTIFIER, import_token.location);
    callee->as.identifier.name = "@import";

    ASTFunctionCallNode* call_node = (ASTFunctionCallNode*)arena_->alloc(sizeof(ASTFunctionCallNode));
    if (!call_node) error("Out of memory");
    call_node->callee = callee;

    void* array_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!array_mem) error("Out of memory");
    call_node->args = new (array_mem) DynamicArray<ASTNode*>(*arena_);

    // The argument is the string literal
    ASTNode* arg = createNodeAt(NODE_STRING_LITERAL, module_token.location);
    arg->as.string_literal.value = module_token.value.identifier;
    call_node->args->append(arg);

    ASTNode* node = createNodeAt(NODE_FUNCTION_CALL, import_token.location);
    node->as.function_call = call_node;
    return node;
}

ASTNode* Parser::parseTopLevelItem() {
    switch (peek().type) {
        case TOKEN_FN:
            return parseFnDecl();
        case TOKEN_VAR:
        case TOKEN_CONST:
            return parseVarDecl();
        case TOKEN_STRUCT: {
            ASTNode* struct_decl = parseStructDeclaration();
            expect(TOKEN_SEMICOLON, "Expected ';' after top-level struct declaration");
            return struct_decl;
        }
        case TOKEN_UNION: {
            ASTNode* union_decl = parseUnionDeclaration();
            expect(TOKEN_SEMICOLON, "Expected ';' after top-level union declaration");
            return union_decl;
        }
        default:
            error("Expected a top-level declaration (function, var, or const)");
            return NULL; // Unreachable
    }
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
    if (!struct_decl) {
        error("Out of memory");
    }
    struct_decl->fields = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!struct_decl->fields) {
        error("Out of memory");
    }
    new (struct_decl->fields) DynamicArray<ASTNode*>(*arena_);

    // Handle fields
    while (peek().type != TOKEN_RBRACE && !is_at_end()) {
        if (peek().type == TOKEN_FN || peek().type == TOKEN_PUB) {
            error("Methods are not supported in struct declarations in bootstrap compiler");
        }

        Token name_token = expect(TOKEN_IDENTIFIER, "Expected field name in struct declaration");
        expect(TOKEN_COLON, "Expected ':' after field name");
        ASTNode* type_node = parseType();

        if (peek().type == TOKEN_EQUAL) {
            error("Default field values are not supported in bootstrap compiler");
        }

        ASTStructFieldNode* field_data = (ASTStructFieldNode*)arena_->alloc(sizeof(ASTStructFieldNode));
        if (!field_data) {
            error("Out of memory");
        }
        field_data->name = name_token.value.identifier;
        field_data->name_loc = name_token.location;
        field_data->type = type_node;

        ASTNode* field_node = createNode(NODE_STRUCT_FIELD);
        field_node->loc = name_token.location;
        field_node->as.struct_field = field_data;

        struct_decl->fields->append(field_node);

        // If the next token is not a closing brace, it must be a comma.
        if (peek().type != TOKEN_RBRACE) {
            expect(TOKEN_COMMA, "Expected ',' or '}' after struct field");
        }
    }

    expect(TOKEN_RBRACE, "Expected '}' to end struct declaration");

    ASTNode* node = createNodeAt(NODE_STRUCT_DECL, struct_token.location);
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

    ASTNode* type_node = NULL;
    if (match(TOKEN_COLON)) {
        // The type can be a simple type name or a container declaration.
        if (peek().type == TOKEN_STRUCT || peek().type == TOKEN_UNION || peek().type == TOKEN_ENUM) {
            // Let parsePrimaryExpr handle the container declaration, as it knows how.
            type_node = parsePrimaryExpr();
        } else {
            // Otherwise, parse it as a standard type expression (pointer, array, simple name).
            type_node = parseType();
        }
    }

    // Parse optional initializer
    ASTNode* initializer_node = NULL;
    if (match(TOKEN_EQUAL)) {
        initializer_node = parseExpression();
        // If it's a named error set, update its name in the catalogue.
        if (initializer_node && initializer_node->type == NODE_ERROR_SET_DEFINITION) {
            initializer_node->as.error_set_decl->name = name_token.value.identifier;
            catalogue_->updateLastSetName(name_token.value.identifier);
        }
    }

    if (!type_node && !initializer_node) {
        error("Variable declaration must have either a type or an initializer");
    }

    expect(TOKEN_SEMICOLON, "Expected ';' after variable declaration");

    ASTVarDeclNode* var_decl = (ASTVarDeclNode*)arena_->alloc(sizeof(ASTVarDeclNode));
    if (!var_decl) {
        error("Out of memory");
    }
    var_decl->name = name_token.value.identifier;
    var_decl->name_loc = name_token.location;
    var_decl->type = type_node;
    var_decl->initializer = initializer_node;
    var_decl->is_const = is_const;
    var_decl->is_mut = is_mut;

    // Create the top-level ASTNode for the declaration *before* creating the symbol,
    // so we can link the symbol to its declaration node.
    ASTNode* node = createNode(NODE_VAR_DECL);
    node->loc = keyword_token.location;
    node->as.var_decl = var_decl;

    // Resolve the type and create the symbol for the symbol table.
    Type* symbol_type = resolveAndVerifyType(type_node);

    Symbol symbol = SymbolBuilder(*arena_)
        .withName(name_token.value.identifier)
        .ofType(SYMBOL_VARIABLE)
        .withType(symbol_type)
        .atLocation(name_token.location)
        .definedBy(node->as.var_decl) // Link the symbol to its declaration details
        .withFlags(0) // Semantic flags will be set by TypeChecker
        .build();

    symbol_table_->insert(symbol);

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
    if (!for_stmt_node) {
        error("Out of memory");
    }
    for_stmt_node->iterable_expr = iterable_expr;
    for_stmt_node->item_name = item_name;
    for_stmt_node->index_name = index_name;
    for_stmt_node->body = body;

    ASTNode* node = createNodeAt(NODE_FOR_STMT, for_token.location);
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

    ASTNode* node = createNodeAt(NODE_DEFER_STMT, defer_token.location);
    node->as.defer_stmt = defer_stmt;

    return node;
}


/**
 * @brief Parses a top-level function declaration.
 *
 * This function handles the parsing of a complete function, including its name,
 * parameters (currently unsupported), return type, and body.
 *
 * Grammar:
 * `fn IDENT '(' ')' ('->' type_expr)? block_statement`
 *
 * @note This parser currently enforces that the parameter list is empty.
 * @return A pointer to the ASTNode representing the function declaration.
 */
ASTNode* Parser::parseFnDecl() {
    Token fn_token = expect(TOKEN_FN, "Expected 'fn' keyword");
    Token name_token = expect(TOKEN_IDENTIFIER, "Expected function name after 'fn'");

    // Create the function declaration node early to hold the parameters
    ASTFnDeclNode* fn_decl = (ASTFnDeclNode*)arena_->alloc(sizeof(ASTFnDeclNode));
    if (!fn_decl) {
        error("Out of memory");
    }

    // Create and insert the symbol for the function itself into the current scope.
    Symbol fn_symbol = SymbolBuilder(*arena_)
        .withName(name_token.value.identifier)
        .ofType(SYMBOL_FUNCTION)
        .withType(NULL) // TODO: Create a function type object
        .atLocation(name_token.location)
        .definedBy(fn_decl)
        .build();

    symbol_table_->insert(fn_symbol);
    fn_decl->name = name_token.value.identifier;
    fn_decl->params = (DynamicArray<ASTParamDeclNode*>*)arena_->alloc(sizeof(DynamicArray<ASTParamDeclNode*>));
    if (!fn_decl->params) {
        error("Out of memory");
    }
    new (fn_decl->params) DynamicArray<ASTParamDeclNode*>(*arena_);
    fn_decl->return_type = NULL;
    fn_decl->body = NULL;


    bool is_generic = false;
    GenericDefinitionKind first_generic_kind = GENERIC_KIND_COMPTIME;

    expect(TOKEN_LPAREN, "Expected '(' after function name");
    if (peek().type != TOKEN_RPAREN) {
        do {
            bool is_comptime = match(TOKEN_COMPTIME);
            bool is_anytype = match(TOKEN_ANYTYPE);
            bool is_type_param = false;

            const char* param_name = NULL;
            ASTNode* param_type_node = NULL;
            SourceLocation param_loc = peek().location;

            if (is_anytype) {
                Token param_name_token = expect(TOKEN_IDENTIFIER, "Expected parameter name after 'anytype'");
                param_name = param_name_token.value.identifier;
                param_loc = param_name_token.location;
                if (!is_generic) {
                    is_generic = true;
                    first_generic_kind = GENERIC_KIND_ANYTYPE;
                }
                // Provide a pseudo-type node for 'anytype'
                param_type_node = createNode(NODE_TYPE_NAME);
                param_type_node->loc = param_loc;
                param_type_node->as.type_name.name = "anytype";
            } else {
                Token param_name_token = expect(TOKEN_IDENTIFIER, "Expected parameter name");
                param_name = param_name_token.value.identifier;
                param_loc = param_name_token.location;
                expect(TOKEN_COLON, "Expected ':' after parameter name");

                if (peek().type == TOKEN_TYPE) {
                    Token type_token = advance();
                    is_type_param = true;
                    if (!is_generic) {
                        is_generic = true;
                        first_generic_kind = GENERIC_KIND_TYPE_PARAM;
                    }
                    param_type_node = createNode(NODE_TYPE_NAME);
                    param_type_node->loc = type_token.location;
                    param_type_node->as.type_name.name = "type";
                } else if (peek().type == TOKEN_ANYTYPE) {
                    Token anytype_token = advance();
                    is_anytype = true;
                    if (!is_generic) {
                        is_generic = true;
                        first_generic_kind = GENERIC_KIND_ANYTYPE;
                    }
                    param_type_node = createNode(NODE_TYPE_NAME);
                    param_type_node->loc = anytype_token.location;
                    param_type_node->as.type_name.name = "anytype";
                } else {
                    param_type_node = parseType();
                }
            }

            if (is_comptime && !is_generic) {
                is_generic = true;
                first_generic_kind = GENERIC_KIND_COMPTIME;
            }

            ASTParamDeclNode* param_decl = (ASTParamDeclNode*)arena_->alloc(sizeof(ASTParamDeclNode));
            if (!param_decl) {
                error("Out of memory");
            }
            param_decl->name = param_name;
            param_decl->type = param_type_node;
            param_decl->is_comptime = is_comptime;
            param_decl->is_anytype = is_anytype;
            param_decl->is_type_param = is_type_param;

            fn_decl->params->append(param_decl);
        } while (match(TOKEN_COMMA));
    }
    expect(TOKEN_RPAREN, "Expected ')' after parameter list");

    if (is_generic) {
        generic_catalogue_->addDefinition(name_token.value.identifier, fn_token.location, first_generic_kind);
    }

    // Update the symbol to reflect generic status if needed.
    Symbol* inserted_sym = symbol_table_->lookupInCurrentScope(name_token.value.identifier);
    if (inserted_sym) {
        inserted_sym->is_generic = is_generic;
    }

    ASTNode* return_type_node = NULL;
    // A return type is optional. If the next token is not a '{',
    // we assume it's a type expression. It might have `->` or not.
    if (peek().type != TOKEN_LBRACE) {
        if(peek().type == TOKEN_ARROW) {
            match(TOKEN_ARROW);
        }
        return_type_node = parseType();
    } else {
        // If there's no type, it defaults to void.
        return_type_node = createNode(NODE_TYPE_NAME);
        // We need to set the location for this implicit node.
        // Let's use the location of the preceding ')'
        SourceLocation loc = tokens_[current_index_ - 1].location;
        return_type_node->loc = loc;
        return_type_node->as.type_name.name = "void";
    }

    ASTNode* body_node = parseBlockStatement();
    if (body_node == NULL) {
        error("Failed to parse function body");
    }

    fn_decl->return_type = return_type_node;
    fn_decl->body = body_node;

    ASTNode* node = createNode(NODE_FN_DECL);
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
Type* Parser::resolveAndVerifyType(ASTNode* type_node) {
    if (type_node == NULL) {
        return NULL;
    }
    if (type_node->type == NODE_TYPE_NAME) {
        Type* resolved_type = resolvePrimitiveTypeName(type_node->as.type_name.name);
        // It's not the parser's job to fail on an unknown type,
        // but the TypeChecker's. Return NULL and let it handle it.
        return resolved_type;
    } else if (type_node->type == NODE_POINTER_TYPE) {
        Type* base_type = resolveAndVerifyType(type_node->as.pointer_type.base);
        if (base_type == NULL) {
            return NULL; // Propagate the failure
        }
        return createPointerType(*arena_, base_type, type_node->as.pointer_type.is_const, type_interner_);
    }
    // Let the TypeChecker handle unsupported types.
    return NULL;
}

ASTNode* Parser::parseStatement() {
    switch (peek().type) {
        case TOKEN_CONST:
        case TOKEN_VAR:
            return parseVarDecl();
        case TOKEN_DEFER:
            return parseDeferStatement();
        case TOKEN_ERRDEFER:
            return parseErrDeferStatement();
        case TOKEN_RETURN:
            return parseReturnStatement();
        case TOKEN_COMPTIME:
            return parseComptimeBlock();
        case TOKEN_IF:
            return parseIfStatement();
        case TOKEN_FOR:
            return parseForStatement();
        case TOKEN_WHILE:
            return parseWhileStatement();
        case TOKEN_BREAK:
            return parseBreakStatement();
        case TOKEN_CONTINUE:
            return parseContinueStatement();
        case TOKEN_LBRACE:
            return parseBlockStatement();
        case TOKEN_SEMICOLON: {
            Token semi_token = advance(); // Consume ';'
            ASTNode* empty_stmt_node = createNodeAt(NODE_EMPTY_STMT, semi_token.location);
            return empty_stmt_node;
        }
        default: {
            ASTNode* expr = parseExpression();
            if (expr != NULL) {
                expect(TOKEN_SEMICOLON, "Expected ';' after expression statement");

                ASTNode* stmt_node = createNode(NODE_EXPRESSION_STMT);
                stmt_node->loc = expr->loc;
                stmt_node->as.expression_stmt.expression = expr;
                return stmt_node;
            } else {
                error("Expected a statement");
                return NULL; // Unreachable
            }
        }
    }
}

ASTNode* Parser::parseBlockStatement() {
    Token lbrace_token = expect(TOKEN_LBRACE, "Expected '{' to start a block");

    symbol_table_->enterScope();

    DynamicArray<ASTNode*>* statements = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!statements) {
        error("Out of memory");
    }
    new (statements) DynamicArray<ASTNode*>(*arena_); // Placement new

    while (!is_at_end() && peek().type != TOKEN_RBRACE) {
        statements->append(parseStatement());
    }
    expect(TOKEN_RBRACE, "Expected '}' to end a block");

    symbol_table_->exitScope();

    ASTNode* block_node = createNode(NODE_BLOCK_STMT);
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
        if (peek().type == TOKEN_IF) {
            else_block = parseIfStatement();
        } else {
            else_block = parseBlockStatement();
        }
    }

    ASTIfStmtNode* if_stmt_node = (ASTIfStmtNode*)arena_->alloc(sizeof(ASTIfStmtNode));
    if (!if_stmt_node) {
        error("Out of memory");
    }
    if_stmt_node->condition = condition;
    if_stmt_node->then_block = then_block;
    if_stmt_node->else_block = else_block;

    ASTNode* node = (ASTNode*)arena_->alloc(sizeof(ASTNode));
    if (!node) {
        error("Out of memory");
    }
    node->type = NODE_IF_STMT;
    node->loc = if_token.location;
    node->resolved_type = NULL;
    node->as.if_stmt = if_stmt_node;

    return node;
}

/**
 * @brief Parses a break statement.
 *        Grammar: `'break' ';'`
 * @return A pointer to the ASTNode representing the break statement.
 */
ASTNode* Parser::parseBreakStatement() {
    Token break_token = expect(TOKEN_BREAK, "Expected 'break' keyword");
    expect(TOKEN_SEMICOLON, "Expected ';' after 'break'");

    ASTNode* node = createNodeAt(NODE_BREAK_STMT, break_token.location);
    // ASTBreakStmtNode is empty, so no fields to set.

    return node;
}

/**
 * @brief Parses a continue statement.
 *        Grammar: `'continue' ';'`
 * @return A pointer to the ASTNode representing the continue statement.
 */
ASTNode* Parser::parseContinueStatement() {
    Token continue_token = expect(TOKEN_CONTINUE, "Expected 'continue' keyword");
    expect(TOKEN_SEMICOLON, "Expected ';' after 'continue'");

    ASTNode* node = createNodeAt(NODE_CONTINUE_STMT, continue_token.location);
    // ASTContinueStmtNode is empty, so no fields to set.

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

    ASTNode* node = createNodeAt(NODE_WHILE_STMT, while_token.location);
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

    ASTNode* node = createNodeAt(NODE_RETURN_STMT, return_token.location);
    node->as.return_stmt = return_stmt;

    return node;
}

ASTNode* Parser::parseType() {
    // Handle 'const' qualifier by skipping it for now in the bootstrap compiler
    // or we could wrap it. For now, let's just skip to the actual type.
    while (match(TOKEN_CONST)) {}

    ASTNode* left = NULL;
    if (peek().type == TOKEN_STAR) {
        left = parsePointerType();
    } else if (peek().type == TOKEN_LBRACKET) {
        left = parseArrayType();
    } else if (peek().type == TOKEN_BANG) {
        left = parseErrorUnionType();
    } else if (peek().type == TOKEN_QUESTION) {
        left = parseOptionalType();
    } else if (peek().type == TOKEN_FN) {
        left = parseFunctionType();
    } else if (peek().type == TOKEN_ERROR_SET) {
        left = parseErrorSetDefinition();
    } else if (peek().type == TOKEN_UNION || peek().type == TOKEN_STRUCT || peek().type == TOKEN_ENUM) {
        left = parsePrimaryExpr();
    } else if (peek().type == TOKEN_IDENTIFIER) {
        Token type_name_token = advance();
        left = createNodeAt(NODE_TYPE_NAME, type_name_token.location);
        left->as.type_name.name = type_name_token.value.identifier;
    } else {
        error("Expected a type expression");
    }

    // Check for binary type operators (! for error union, || for error set merge)
    while (peek().type == TOKEN_BANG || peek().type == TOKEN_PIPE_PIPE) {
        if (peek().type == TOKEN_BANG) {
            Token bang_token = advance();
            ASTNode* payload_type = parseType();

            ASTErrorUnionTypeNode* eu_node = (ASTErrorUnionTypeNode*)arena_->alloc(sizeof(ASTErrorUnionTypeNode));
            if (!eu_node) {
                error("Out of memory");
            }
            eu_node->error_set = left;
            eu_node->payload_type = payload_type;
            eu_node->loc = bang_token.location;

            ASTNode* node = createNodeAt(NODE_ERROR_UNION_TYPE, bang_token.location);
            node->as.error_union_type = eu_node;
            left = node;
        } else {
            Token pipe_token = advance();
            ASTNode* right = parseType();

            ASTErrorSetMergeNode* merge_data = (ASTErrorSetMergeNode*)arena_->alloc(sizeof(ASTErrorSetMergeNode));
            if (!merge_data) {
                error("Out of memory");
            }
            merge_data->left = left;
            merge_data->right = right;

            ASTNode* merge_node = createNodeAt(NODE_ERROR_SET_MERGE, pipe_token.location);
            merge_node->as.error_set_merge = merge_data;
            left = merge_node;
        }
    }

    return left;
}

ASTNode* Parser::parsePointerType() {
    Token start_token = expect(TOKEN_STAR, "Expected '*' for pointer type");
    bool is_const = match(TOKEN_CONST);
    ASTNode* base_type = parseType();

    ASTNode* node = createNodeAt(NODE_POINTER_TYPE, start_token.location);
    node->as.pointer_type.base = base_type;
    node->as.pointer_type.is_const = is_const;

    return node;
}

ASTNode* Parser::parseErrorUnionType() {
    Token bang_token = advance(); // Consume '!'
    ASTNode* payload_type = parseType();

    ASTErrorUnionTypeNode* eu_node = (ASTErrorUnionTypeNode*)arena_->alloc(sizeof(ASTErrorUnionTypeNode));
    if (!eu_node) {
        error("Out of memory");
    }
    eu_node->error_set = NULL; // Inferred error set
    eu_node->payload_type = payload_type;
    eu_node->loc = bang_token.location;

    ASTNode* node = createNodeAt(NODE_ERROR_UNION_TYPE, bang_token.location);
    node->as.error_union_type = eu_node;

    return node;
}

ASTNode* Parser::parseOptionalType() {
    Token question_token = advance(); // Consume '?'
    ASTNode* payload_type = parseType();

    ASTOptionalTypeNode* opt_node = (ASTOptionalTypeNode*)arena_->alloc(sizeof(ASTOptionalTypeNode));
    if (!opt_node) {
        error("Out of memory");
    }
    opt_node->payload_type = payload_type;
    opt_node->loc = question_token.location;

    ASTNode* node = createNodeAt(NODE_OPTIONAL_TYPE, question_token.location);
    node->as.optional_type = opt_node;

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

    ASTNode* node = createNodeAt(NODE_ARRAY_TYPE, lbracket_token.location);
    node->as.array_type.element_type = element_type;
    node->as.array_type.size = size_expr; // Will be NULL for slices

    return node;
}

ASTNode* Parser::parseFunctionType() {
    Token fn_token = expect(TOKEN_FN, "Expected 'fn'");
    expect(TOKEN_LPAREN, "Expected '(' after 'fn'");

    DynamicArray<ASTNode*>* params = (DynamicArray<ASTNode*>*)arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!params) error("Out of memory");
    new (params) DynamicArray<ASTNode*>(*arena_);

    if (peek().type != TOKEN_RPAREN) {
        do {
            params->append(parseType());
        } while (match(TOKEN_COMMA));
    }
    expect(TOKEN_RPAREN, "Expected ')' after function type parameters");

    ASTNode* return_type = parseType();

    ASTFunctionTypeNode* ft_node = (ASTFunctionTypeNode*)arena_->alloc(sizeof(ASTFunctionTypeNode));
    if (!ft_node) error("Out of memory");
    ft_node->params = params;
    ft_node->return_type = return_type;

    ASTNode* node = createNodeAt(NODE_FUNCTION_TYPE, fn_token.location);
    node->as.function_type = ft_node;
    return node;
}

ASTNode* Parser::parsePtrCastExpr() {
    Token ptr_cast_token = expect(TOKEN_AT_PTRCAST, "Expected '@ptrCast'");
    expect(TOKEN_LPAREN, "Expected '(' after '@ptrCast'");

    ASTNode* target_type = parseType();
    expect(TOKEN_COMMA, "Expected ',' after target type in @ptrCast");

    ASTNode* expr = parseExpression();
    expect(TOKEN_RPAREN, "Expected ')' after @ptrCast expression");

    ASTPtrCastNode* ptr_cast_data = (ASTPtrCastNode*)arena_->alloc(sizeof(ASTPtrCastNode));
    if (!ptr_cast_data) error("Out of memory");
    ptr_cast_data->target_type = target_type;
    ptr_cast_data->expr = expr;

    ASTNode* node = createNodeAt(NODE_PTR_CAST, ptr_cast_token.location);
    node->as.ptr_cast = ptr_cast_data;
    return node;
}

ASTNode* Parser::parseNumericCastExpr(NodeType type) {
    Token cast_token = advance(); // Consume @intCast or @floatCast
    expect(TOKEN_LPAREN, "Expected '(' after built-in");

    ASTNode* target_type = parseType();
    expect(TOKEN_COMMA, "Expected ',' after target type in built-in");

    ASTNode* expr = parseExpression();
    expect(TOKEN_RPAREN, "Expected ')' after built-in expression");

    ASTNumericCastNode* cast_data = (ASTNumericCastNode*)arena_->alloc(sizeof(ASTNumericCastNode));
    if (!cast_data) error("Out of memory");
    cast_data->target_type = target_type;
    cast_data->expr = expr;

    ASTNode* node = createNodeAt(type, cast_token.location);
    node->as.numeric_cast = cast_data;
    return node;
}

ASTNode* Parser::parseBuiltinCall(const char* name, SourceLocation loc) {
    expect(TOKEN_LPAREN, "Expected '(' after built-in");

    ASTFunctionCallNode* call_data = (ASTFunctionCallNode*)arena_->alloc(sizeof(ASTFunctionCallNode));
    if (!call_data) error("Out of memory");

    ASTNode* callee = createNodeAt(NODE_IDENTIFIER, loc);
    callee->as.identifier.name = name;
    call_data->callee = callee;

    void* array_mem = arena_->alloc(sizeof(DynamicArray<ASTNode*>));
    if (!array_mem) error("Out of memory");
    call_data->args = new (array_mem) DynamicArray<ASTNode*>(*arena_);

    if (plat_strcmp(name, "@sizeOf") == 0 || plat_strcmp(name, "@alignOf") == 0) {
        call_data->args->append(parseType());
    } else if (plat_strcmp(name, "@ptrCast") == 0 || plat_strcmp(name, "@intCast") == 0 ||
               plat_strcmp(name, "@floatCast") == 0) {
        call_data->args->append(parseType());
        expect(TOKEN_COMMA, "Expected ',' after first argument of built-in");
        call_data->args->append(parseExpression());
    }

    expect(TOKEN_RPAREN, "Expected ')' after built-in arguments");

    ASTNode* node = createNodeAt(NODE_FUNCTION_CALL, loc);
    node->as.function_call = call_data;
    return node;
}

ASTNode* Parser::parseOffsetOfExpr() {
    SourceLocation loc = advance().location; // Consume @offsetOf
    expect(TOKEN_LPAREN, "Expected '(' after '@offsetOf'");

    ASTNode* type_expr = parseType();
    expect(TOKEN_COMMA, "Expected ',' after type argument of '@offsetOf'");

    Token field_token = expect(TOKEN_STRING_LITERAL, "Expected string literal for field name in '@offsetOf'");
    const char* field_name = field_token.value.identifier;

    expect(TOKEN_RPAREN, "Expected ')' after '@offsetOf' arguments");

    ASTOffsetOfNode* offset_data = (ASTOffsetOfNode*)arena_->alloc(sizeof(ASTOffsetOfNode));
    if (!offset_data) error("Out of memory");

    offset_data->type_expr = type_expr;
    offset_data->field_name = field_name;

    ASTNode* node = createNodeAt(NODE_OFFSET_OF, loc);
    node->as.offset_of = offset_data;
    return node;
}
