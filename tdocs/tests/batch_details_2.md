# Z98 Test Batch 2 Technical Specification

## High-Level Objective
Technical validation of compiler components.

This test batch comprises 114 individual verification units for exhaustive coverage.

## Test Case Specifications
### `test_ASTNode_IntegerLiteral`
- **Implementation Source**: `tests/test_ast.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_INTEGER_LITERAL` matches `node.type`
  2. Assert that `1` matches `node.loc.file_id`
  3. Assert that `10` matches `node.loc.line`
  4. Assert that `5` matches `node.loc.column`
  5. Assert that `42` matches `node.as.integer_literal.value`
  ```

### `test_ASTNode_FloatLiteral`
- **Implementation Source**: `tests/test_ast.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_FLOAT_LITERAL` matches `node.type`
  2. Assert that `1` matches `node.loc.line`
  3. Validate that `node.as.float_literal.value > 3.1 && node.as.float_literal.value < 3.2` is satisfied
  ```

### `test_ASTNode_CharLiteral`
- **Implementation Source**: `tests/test_ast.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_CHAR_LITERAL` matches `node.type`
  2. Assert that `2` matches `node.loc.line`
  3. Assert that `'z'` matches `node.as.char_literal.value`
  ```

### `test_ASTNode_StringLiteral`
- **Implementation Source**: `tests/test_ast.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
hello world
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_STRING_LITERAL` matches `node.type`
  2. Assert that `3` matches `node.loc.line`
  ```

### `test_ASTNode_Identifier`
- **Implementation Source**: `tests/test_ast.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
my_variable
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_IDENTIFIER` matches `node.type`
  2. Assert that `4` matches `node.loc.line`
  ```

### `test_ASTNode_UnaryOp`
- **Implementation Source**: `tests/test_ast.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_UNARY_OP` matches `node.type`
  2. Assert that `TOKEN_MINUS` matches `node.as.unary_op.op`
  3. Validate that `node.as.unary_op.operand not equals null` is satisfied
  4. Assert that `NODE_INTEGER_LITERAL` matches `node.as.unary_op.operand.type`
  5. Assert that `100` matches `node.as.unary_op.operand.as.integer_literal.value`
  ```

### `test_ASTNode_BinaryOp`
- **Implementation Source**: `tests/test_ast.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_BINARY_OP` matches `node.type`
  2. Assert that `TOKEN_PLUS` matches `node.as.binary_op.op`
  3. Validate that `node.as.binary_op.left not equals null` is satisfied
  4. Validate that `node.as.binary_op.right not equals null` is satisfied
  ```

### `test_Parser_ParsePrimaryExpr_IntegerLiteral`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_INTEGER_LITERAL` matches `node.type`
  3. Assert that `123` matches `node.as.integer_literal.value`
  ```

### `test_Parser_ParsePrimaryExpr_FloatLiteral`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_FLOAT_LITERAL` matches `node.type`
  3. Validate that `compare_floats(node.as.float_literal.value, 3.14` is satisfied
  ```

### `test_Parser_ParsePrimaryExpr_CharLiteral`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_CHAR_LITERAL` matches `node.type`
  3. Assert that `'a'` matches `node.as.char_literal.value`
  ```

### `test_Parser_ParsePrimaryExpr_StringLiteral`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_STRING_LITERAL` matches `node.type`
  ```

### `test_Parser_ParsePrimaryExpr_Identifier`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_IDENTIFIER` matches `node.type`
  ```

### `test_Parser_ParsePrimaryExpr_ParenthesizedExpression`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_INTEGER_LITERAL` matches `node.type`
  3. Assert that `42` matches `node.as.integer_literal.value`
  ```

### `test_Parser_FunctionCall_NoArgs`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_FUNCTION_CALL` matches `node.type`
  2. Assert that `NODE_IDENTIFIER` matches `node.as.function_call.callee.type`
  3. Assert that `0` matches `node.as.function_call.args.length`
  ```

### `test_Parser_FunctionCall_WithArgs`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_FUNCTION_CALL` matches `node.type`
  2. Assert that `NODE_IDENTIFIER` matches `node.as.function_call.callee.type`
  3. Assert that `2` matches `node.as.function_call.args.length`
  4. Assert that `NODE_INTEGER_LITERAL` matches `*node.as.function_call.args)[0].type`
  5. Assert that `1` matches `*node.as.function_call.args)[0].as.integer_literal.value`
  6. Assert that `NODE_INTEGER_LITERAL` matches `*node.as.function_call.args)[1].type`
  7. Assert that `2` matches `*node.as.function_call.args)[1].as.integer_literal.value`
  ```

### `test_Parser_FunctionCall_WithTrailingComma`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_FUNCTION_CALL` matches `node.type`
  2. Assert that `2` matches `node.as.function_call.args.length`
  3. Assert that `1` matches `*node.as.function_call.args)[0].as.integer_literal.value`
  4. Assert that `2` matches `*node.as.function_call.args)[1].as.integer_literal.value`
  ```

### `test_Parser_ArrayAccess`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_ARRAY_ACCESS` matches `node.type`
  2. Assert that `NODE_IDENTIFIER` matches `node.as.array_access.array.type`
  3. Assert that `NODE_INTEGER_LITERAL` matches `node.as.array_access.index.type`
  4. Assert that `0` matches `node.as.array_access.index.as.integer_literal.value`
  ```

### `test_Parser_ChainedPostfixOps`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_ARRAY_ACCESS` matches `node.type`
  2. Assert that `NODE_FUNCTION_CALL` matches `callee.type`
  3. Assert that `NODE_IDENTIFIER` matches `callee.as.function_call.callee.type`
  ```

### `test_Parser_CompoundAssignment_Simple`
- **Implementation Source**: `tests/test_parser_compound_assignment.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_COMPOUND_ASSIGNMENT` matches `expr.type`
  3. Assert that `TOKEN_PLUS_EQUAL` matches `expr.as.compound_assignment.op`
  4. Assert that `NODE_IDENTIFIER` matches `left.type`
  5. Assert that `NODE_INTEGER_LITERAL` matches `right.type`
  6. Assert that `5` matches `right.as.integer_literal.value`
  ```

### `test_Parser_CompoundAssignment_AllOperators`
- **Implementation Source**: `tests/test_parser_compound_assignment.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_COMPOUND_ASSIGNMENT` matches `expr.type`
  3. Assert that `expectedOps[i]` matches `expr.as.compound_assignment.op`
  ```

### `test_Parser_CompoundAssignment_RightAssociativity`
- **Implementation Source**: `tests/test_parser_compound_assignment.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_COMPOUND_ASSIGNMENT` matches `expr.type`
  3. Assert that `TOKEN_PLUS_EQUAL` matches `expr.as.compound_assignment.op`
  4. Assert that `NODE_IDENTIFIER` matches `left.type`
  5. Assert that `NODE_COMPOUND_ASSIGNMENT` matches `right.type`
  6. Assert that `TOKEN_STAR_EQUAL` matches `right.as.compound_assignment.op`
  ```

### `test_Parser_CompoundAssignment_ComplexRHS`
- **Implementation Source**: `tests/test_parser_compound_assignment.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_COMPOUND_ASSIGNMENT` matches `expr.type`
  3. Assert that `TOKEN_STAR_EQUAL` matches `expr.as.compound_assignment.op`
  4. Assert that `NODE_BINARY_OP` matches `right.type`
  5. Assert that `TOKEN_PLUS` matches `right.as.binary_op.op`
  ```

### `test_Parser_BinaryExpr_SimplePrecedence`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_BINARY_OP` matches `expr.type`
  3. Assert that `TOKEN_PLUS` matches `root.op`
  4. Assert that `NODE_INTEGER_LITERAL` matches `left.type`
  5. Assert that `2` matches `left.as.integer_literal.value`
  6. Assert that `NODE_BINARY_OP` matches `right.type`
  7. Assert that `TOKEN_STAR` matches `right_op.op`
  8. Assert that `NODE_INTEGER_LITERAL` matches `right_op.left.type`
  9. Assert that `3` matches `right_op.left.as.integer_literal.value`
  10. Assert that `NODE_INTEGER_LITERAL` matches `right_op.right.type`
  11. Assert that `4` matches `right_op.right.as.integer_literal.value`
  ```

### `test_Parser_BinaryExpr_LeftAssociativity`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_BINARY_OP` matches `expr.type`
  3. Assert that `TOKEN_MINUS` matches `root.op`
  4. Assert that `NODE_INTEGER_LITERAL` matches `root.right.type`
  5. Assert that `2` matches `root.right.as.integer_literal.value`
  6. Assert that `NODE_BINARY_OP` matches `left.type`
  7. Assert that `TOKEN_MINUS` matches `left_op.op`
  8. Assert that `NODE_INTEGER_LITERAL` matches `left_op.left.type`
  9. Assert that `10` matches `left_op.left.as.integer_literal.value`
  10. Assert that `NODE_INTEGER_LITERAL` matches `left_op.right.type`
  11. Assert that `4` matches `left_op.right.as.integer_literal.value`
  ```

### `test_Parser_TryExpr_Simple`
- **Implementation Source**: `tests/test_parser_try_expr.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
try foo()
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_TRY_EXPR` matches `expr.type`
  3. Validate that `try_expr.expression not equals null` is satisfied
  4. Assert that `NODE_FUNCTION_CALL` matches `try_expr.expression.type`
  5. Assert that `NODE_IDENTIFIER` matches `call_node.callee.type`
  ```

### `test_Parser_TryExpr_Chained`
- **Implementation Source**: `tests/test_parser_try_expr.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
try !foo()
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_TRY_EXPR` matches `expr.type`
  3. Validate that `try_expr.expression not equals null` is satisfied
  4. Assert that `NODE_UNARY_OP` matches `try_expr.expression.type`
  5. Assert that `TOKEN_BANG` matches `unary_op.op`
  6. Validate that `operand not equals null` is satisfied
  7. Assert that `NODE_FUNCTION_CALL` matches `operand.type`
  8. Assert that `NODE_IDENTIFIER` matches `call_node.callee.type`
  ```

### `test_Parser_CatchExpression_Simple`
- **Implementation Source**: `tests/test_parser_catch_expr.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch b
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_CATCH_EXPR` matches `root.type`
  2. Validate that `catch_node.payload not equals null` is satisfied
  3. Assert that `NODE_IDENTIFIER` matches `catch_node.payload.type`
  4. Validate that `catch_node.error_name equals null` is satisfied
  5. Validate that `catch_node.else_expr not equals null` is satisfied
  6. Assert that `NODE_IDENTIFIER` matches `catch_node.else_expr.type`
  ```

### `test_Parser_CatchExpression_WithPayload`
- **Implementation Source**: `tests/test_parser_catch_expr.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch |err| b
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_CATCH_EXPR` matches `root.type`
  2. Validate that `catch_node.payload not equals null` is satisfied
  3. Assert that `NODE_IDENTIFIER` matches `catch_node.payload.type`
  4. Validate that `catch_node.error_name not equals null` is satisfied
  5. Validate that `catch_node.else_expr not equals null` is satisfied
  6. Assert that `NODE_IDENTIFIER` matches `catch_node.else_expr.type`
  ```

### `test_Parser_CatchExpression_MixedAssociativity`
- **Implementation Source**: `tests/test_parser_catch_expr.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch b orelse c
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_CATCH_EXPR` matches `root.type`
  2. Assert that `NODE_IDENTIFIER` matches `catch_node.payload.type`
  3. Validate that `right not equals null` is satisfied
  4. Assert that `NODE_ORELSE_EXPR` matches `right.type`
  5. Assert that `NODE_IDENTIFIER` matches `orelse_node.payload.type`
  6. Assert that `NODE_IDENTIFIER` matches `orelse_node.else_expr.type`
  ```

### `test_Parser_Orelse_IsRightAssociative`
- **Implementation Source**: `tests/parser_associativity_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a orelse b orelse c
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `is_orelse_expr(root` is satisfied
  2. Validate that `is_identifier(root.as.orelse_expr.payload, "a"` is satisfied
  3. Validate that `is_orelse_expr(right_node` is satisfied
  4. Validate that `is_identifier(right_node.as.orelse_expr.payload, "b"` is satisfied
  5. Validate that `is_identifier(right_node.as.orelse_expr.else_expr, "c"` is satisfied
  ```

### `test_Parser_Catch_IsRightAssociative`
- **Implementation Source**: `tests/parser_associativity_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch b catch c
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `is_catch_expr(root` is satisfied
  2. Validate that `is_identifier(root.as.catch_expr.payload, "a"` is satisfied
  3. Validate that `is_catch_expr(right_node` is satisfied
  4. Validate that `is_identifier(right_node.as.catch_expr.payload, "b"` is satisfied
  5. Validate that `is_identifier(right_node.as.catch_expr.else_expr, "c"` is satisfied
  ```

### `test_Parser_CatchOrelse_IsRightAssociative`
- **Implementation Source**: `tests/parser_associativity_test.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch b orelse c
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `is_catch_expr(root` is satisfied
  2. Validate that `is_identifier(root.as.catch_expr.payload, "a"` is satisfied
  3. Validate that `is_orelse_expr(right_node` is satisfied
  4. Validate that `is_identifier(right_node.as.orelse_expr.payload, "b"` is satisfied
  5. Validate that `is_identifier(right_node.as.orelse_expr.else_expr, "c"` is satisfied
  ```

### `test_Parser_CatchExpr_Simple`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch b
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_CATCH_EXPR` matches `expr.type`
  3. Assert that `NODE_IDENTIFIER` matches `root.payload.type`
  4. Assert that `NODE_IDENTIFIER` matches `root.else_expr.type`
  5. Validate that `root.error_name equals null` is satisfied
  ```

### `test_Parser_CatchExpr_RightAssociativity`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch b catch c
  ```
  ```zig
);
    ASSERT_TRUE(root->error_name == NULL);

    // else_expr should be 'b catch c'
    ASTNode* else_expr = root->else_expr;
    ASSERT_EQ(else_expr->type, NODE_CATCH_EXPR);
    ASTCatchExprNode* else_op = else_expr->as.catch_expr;
    ASSERT_EQ(else_op->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(else_op->payload->as.identifier.name,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_CATCH_EXPR` matches `expr.type`
  3. Assert that `NODE_IDENTIFIER` matches `root.payload.type`
  4. Validate that `root.error_name equals null` is satisfied
  5. Assert that `NODE_CATCH_EXPR` matches `else_expr.type`
  6. Assert that `NODE_IDENTIFIER` matches `else_op.payload.type`
  7. Assert that `NODE_IDENTIFIER` matches `else_op.else_expr.type`
  8. Validate that `else_op.error_name equals null` is satisfied
  ```

### `test_Parser_CatchExpr_MixedAssociativity`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a orelse b catch c
  ```
  ```zig
);

    // else_expr should be 'b catch c'
    ASTNode* else_expr = root->else_expr;
    ASSERT_EQ(else_expr->type, NODE_CATCH_EXPR);
    ASTCatchExprNode* else_op = else_expr->as.catch_expr;
    ASSERT_EQ(else_op->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(else_op->payload->as.identifier.name,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_ORELSE_EXPR` matches `expr.type`
  3. Assert that `NODE_IDENTIFIER` matches `root.payload.type`
  4. Assert that `NODE_CATCH_EXPR` matches `else_expr.type`
  5. Assert that `NODE_IDENTIFIER` matches `else_op.payload.type`
  6. Assert that `NODE_IDENTIFIER` matches `else_op.else_expr.type`
  ```

### `test_Parser_OrelseExpr_Simple`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a orelse b
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_ORELSE_EXPR` matches `expr.type`
  3. Assert that `NODE_IDENTIFIER` matches `root.payload.type`
  4. Assert that `NODE_IDENTIFIER` matches `root.else_expr.type`
  ```

### `test_Parser_OrelseExpr_RightAssociativity`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a orelse b orelse c
  ```
  ```zig
);

    // else_expr should be 'b orelse c'
    ASTNode* else_expr = root->else_expr;
    ASSERT_EQ(else_expr->type, NODE_ORELSE_EXPR);
    ASTOrelseExprNode* else_op = else_expr->as.orelse_expr;
    ASSERT_EQ(else_op->payload->type, NODE_IDENTIFIER);
    ASSERT_STREQ(else_op->payload->as.identifier.name,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_ORELSE_EXPR` matches `expr.type`
  3. Assert that `NODE_IDENTIFIER` matches `root.payload.type`
  4. Assert that `NODE_ORELSE_EXPR` matches `else_expr.type`
  5. Assert that `NODE_IDENTIFIER` matches `else_op.payload.type`
  6. Assert that `NODE_IDENTIFIER` matches `else_op.else_expr.type`
  ```

### `test_Parser_OrelseExpr_Precedence`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
a and b orelse c
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expr not equals null` is satisfied
  2. Assert that `NODE_ORELSE_EXPR` matches `expr.type`
  3. Assert that `NODE_IDENTIFIER` matches `root.else_expr.type`
  4. Assert that `NODE_BINARY_OP` matches `payload.type`
  5. Assert that `TOKEN_AND` matches `payload_op.op`
  6. Assert that `NODE_IDENTIFIER` matches `payload_op.left.type`
  7. Assert that `NODE_IDENTIFIER` matches `payload_op.right.type`
  ```

### `test_ASTNode_ContainerDeclarations`
- **Implementation Source**: `tests/test_ast_container_declarations.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `struct_node.fields equals null` is satisfied
  2. Validate that `union_node.fields equals null` is satisfied
  3. Validate that `enum_node.fields equals null` is satisfied
  ```

### `test_Parser_Struct_Error_MissingLBrace`
- **Implementation Source**: `tests/test_parser_errors.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort("struct"` is satisfied
  ```

### `test_Parser_Struct_Error_MissingRBrace`
- **Implementation Source**: `tests/test_parser_errors.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
struct {
  ```
  ```zig
struct { a i32 }
  ```
  ```zig
struct { a : }
  ```
  ```zig
struct { 123 }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort("struct {"` is satisfied
  2. Validate that `expect_statement_parser_abort("struct { a i32 }"` is satisfied
  3. Validate that `expect_statement_parser_abort("struct { a : }"` is satisfied
  4. Validate that `expect_statement_parser_abort("struct { 123 }"` is satisfied
  ```

### `test_Parser_Struct_Error_MissingColon`
- **Implementation Source**: `tests/test_parser_errors.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
struct { a i32 }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort("struct { a i32 }"` is satisfied
  ```

### `test_Parser_Struct_Error_MissingType`
- **Implementation Source**: `tests/test_parser_errors.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
struct { a : }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort("struct { a : }"` is satisfied
  ```

### `test_Parser_Struct_Error_InvalidField`
- **Implementation Source**: `tests/test_parser_errors.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
struct { 123 }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort("struct { 123 }"` is satisfied
  ```

### `test_Parser_StructDeclaration_Simple`
- **Implementation Source**: `tests/test_parser_struct.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
struct { x: i32 }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_STRUCT_DECL` matches `node.type`
  3. Validate that `struct_decl not equals null` is satisfied
  4. Assert that `1` matches `struct_decl.fields.length`
  5. Assert that `NODE_STRUCT_FIELD` matches `field_node.type`
  6. Validate that `field.type not equals null` is satisfied
  7. Assert that `NODE_TYPE_NAME` matches `field.type.type`
  ```

### `test_Parser_StructDeclaration_Empty`
- **Implementation Source**: `tests/test_parser_struct.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
struct {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_STRUCT_DECL` matches `node.type`
  3. Validate that `struct_decl not equals null` is satisfied
  4. Assert that `0` matches `struct_decl.fields.length`
  ```

### `test_Parser_StructDeclaration_MultipleFields`
- **Implementation Source**: `tests/test_parser_struct.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
struct { a: i32, b: bool, c: *u8 }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_STRUCT_DECL` matches `node.type`
  3. Validate that `struct_decl not equals null` is satisfied
  4. Assert that `3` matches `struct_decl.fields.length`
  5. Assert that `NODE_STRUCT_FIELD` matches `field_node_a.type`
  6. Assert that `NODE_TYPE_NAME` matches `field_a.type.type`
  7. Assert that `NODE_STRUCT_FIELD` matches `field_node_b.type`
  8. Assert that `NODE_TYPE_NAME` matches `field_b.type.type`
  9. Assert that `NODE_STRUCT_FIELD` matches `field_node_c.type`
  10. Assert that `NODE_POINTER_TYPE` matches `field_c.type.type`
  11. Assert that `NODE_TYPE_NAME` matches `base_type.type`
  ```

### `test_Parser_StructDeclaration_WithTrailingComma`
- **Implementation Source**: `tests/test_parser_struct.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
struct { x: i32, }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_STRUCT_DECL` matches `node.type`
  3. Validate that `struct_decl not equals null` is satisfied
  4. Assert that `1` matches `struct_decl.fields.length`
  ```

### `test_Parser_StructDeclaration_ComplexFieldType`
- **Implementation Source**: `tests/test_parser_struct.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
struct { ptr: *[8]u8 }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_STRUCT_DECL` matches `node.type`
  3. Assert that `1` matches `struct_decl.fields.length`
  4. Assert that `NODE_POINTER_TYPE` matches `type.type`
  5. Assert that `NODE_ARRAY_TYPE` matches `array_type.type`
  6. Validate that `array_type.as.array_type.size not equals null` is satisfied
  7. Assert that `NODE_INTEGER_LITERAL` matches `array_type.as.array_type.size.type`
  8. Assert that `8` matches `array_type.as.array_type.size.as.integer_literal.value`
  9. Assert that `NODE_TYPE_NAME` matches `array_type.as.array_type.element_type.type`
  ```

### `test_ParserBug_TopLevelUnion`
- **Implementation Source**: `tests/test_parser_bug.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
union {};
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Validate that `node.type equals NODE_BLOCK_STMT` is satisfied
  3. Validate that `block.statements.length` is satisfied
  4. Validate that `union_node not equals null` is satisfied
  5. Validate that `union_node.type equals NODE_UNION_DECL` is satisfied
  ```

### `test_ParserBug_TopLevelStruct`
- **Implementation Source**: `tests/test_parser_bug.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
struct {};
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Validate that `node.type equals NODE_BLOCK_STMT` is satisfied
  3. Validate that `block.statements.length` is satisfied
  4. Validate that `struct_node not equals null` is satisfied
  5. Validate that `struct_node.type equals NODE_STRUCT_DECL` is satisfied
  ```

### `test_ParserBug_UnionFieldNodeType`
- **Implementation Source**: `tests/test_parser_bug.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
union { a: i32, };
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `union_decl.fields.length` is satisfied
  2. Validate that `field_node.type equals NODE_STRUCT_FIELD` is satisfied
  ```

### `test_Parser_Enum_Empty`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_ENUM_DECL` matches `node.type`
  3. Validate that `enum_decl not equals null` is satisfied
  4. Validate that `enum_decl.backing_type equals null` is satisfied
  5. Assert that `0` matches `enum_decl.fields.length`
  ```

### `test_Parser_Enum_SimpleMembers`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_ENUM_DECL` matches `node.type`
  3. Validate that `enum_decl not equals null` is satisfied
  4. Validate that `enum_decl.backing_type equals null` is satisfied
  5. Assert that `3` matches `enum_decl.fields.length`
  6. Assert that `NODE_VAR_DECL` matches `member1_node.type`
  7. Validate that `member1.type equals null` is satisfied
  8. Validate that `member1.initializer equals null` is satisfied
  9. Assert that `NODE_VAR_DECL` matches `member3_node.type`
  10. Validate that `member3.initializer equals null` is satisfied
  ```

### `test_Parser_Enum_TrailingComma`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_ENUM_DECL` matches `node.type`
  3. Assert that `2` matches `enum_decl.fields.length`
  ```

### `test_Parser_Enum_WithValues`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_ENUM_DECL` matches `node.type`
  3. Assert that `2` matches `enum_decl.fields.length`
  4. Validate that `member1.initializer not equals null` is satisfied
  5. Assert that `NODE_INTEGER_LITERAL` matches `member1.initializer.type`
  6. Assert that `1` matches `member1.initializer.as.integer_literal.value`
  7. Validate that `member2.initializer not equals null` is satisfied
  8. Assert that `NODE_INTEGER_LITERAL` matches `member2.initializer.type`
  9. Assert that `20` matches `member2.initializer.as.integer_literal.value`
  ```

### `test_Parser_Enum_MixedMembers`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_ENUM_DECL` matches `node.type`
  3. Assert that `3` matches `enum_decl.fields.length`
  4. Validate that `member1.initializer equals null` is satisfied
  5. Validate that `member2.initializer not equals null` is satisfied
  6. Validate that `member3.initializer equals null` is satisfied
  ```

### `test_Parser_Enum_WithBackingType`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_ENUM_DECL` matches `node.type`
  3. Validate that `enum_decl.backing_type not equals null` is satisfied
  4. Assert that `NODE_TYPE_NAME` matches `enum_decl.backing_type.type`
  5. Assert that `2` matches `enum_decl.fields.length`
  ```

### `test_Parser_Enum_SyntaxError_MissingOpeningBrace`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_Enum_SyntaxError_MissingClosingBrace`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
);
}

TEST_FUNC(Parser_Enum_SyntaxError_NoComma) {
    return expect_parser_abort(
  ```
  ```zig
);
}

TEST_FUNC(Parser_Enum_SyntaxError_InvalidMember) {
    return expect_parser_abort(
  ```
  ```zig
);
}

TEST_FUNC(Parser_Enum_SyntaxError_MissingInitializer) {
    return expect_parser_abort(
  ```
  ```zig
);
}

TEST_FUNC(Parser_Enum_SyntaxError_BackingTypeNoParens) {
    return expect_parser_abort(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `node not equals null` is satisfied
  3. Assert that `NODE_ENUM_DECL` matches `node.type`
  4. Assert that `1` matches `enum_decl.fields.length`
  5. Validate that `member1.initializer not equals null` is satisfied
  6. Assert that `NODE_BINARY_OP` matches `member1.initializer.type`
  7. Assert that `TOKEN_PLUS` matches `bin_op.op`
  8. Assert that `NODE_INTEGER_LITERAL` matches `bin_op.left.type`
  9. Assert that `1` matches `bin_op.left.as.integer_literal.value`
  10. Assert that `NODE_INTEGER_LITERAL` matches `bin_op.right.type`
  11. Assert that `2` matches `bin_op.right.as.integer_literal.value`
  ```

### `test_Parser_Enum_SyntaxError_NoComma`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_Enum_SyntaxError_InvalidMember`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_Enum_SyntaxError_MissingInitializer`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_Enum_SyntaxError_BackingTypeNoParens`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_Enum_ComplexInitializer`
- **Implementation Source**: `tests/test_parser_enums.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_ENUM_DECL` matches `node.type`
  3. Assert that `1` matches `enum_decl.fields.length`
  4. Validate that `member1.initializer not equals null` is satisfied
  5. Assert that `NODE_BINARY_OP` matches `member1.initializer.type`
  6. Assert that `TOKEN_PLUS` matches `bin_op.op`
  7. Assert that `NODE_INTEGER_LITERAL` matches `bin_op.left.type`
  8. Assert that `1` matches `bin_op.left.as.integer_literal.value`
  9. Assert that `NODE_INTEGER_LITERAL` matches `bin_op.right.type`
  10. Assert that `2` matches `bin_op.right.as.integer_literal.value`
  ```

### `test_Parser_FnDecl_ValidEmpty`
- **Implementation Source**: `tests/test_parser_fn_decl.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> i32 {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `fn_decl_node not equals null` is satisfied
  2. Assert that `NODE_FN_DECL` matches `fn_decl_node.type`
  3. Validate that `fn_decl.params not equals null` is satisfied
  4. Assert that `0` matches `fn_decl.params.length`
  5. Validate that `fn_decl.return_type not equals null` is satisfied
  6. Assert that `NODE_TYPE_NAME` matches `fn_decl.return_type.type`
  7. Validate that `fn_decl.body not equals null` is satisfied
  8. Assert that `NODE_BLOCK_STMT` matches `fn_decl.body.type`
  9. Validate that `block.statements not equals null` is satisfied
  10. Assert that `0` matches `block.statements.length`
  ```

### `test_Parser_FnDecl_Valid_NoArrow`
- **Implementation Source**: `tests/test_parser_fn_decl.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() i32 {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `fn_decl_node not equals null` is satisfied
  2. Assert that `NODE_FN_DECL` matches `fn_decl_node.type`
  3. Validate that `fn_decl.return_type not equals null` is satisfied
  4. Assert that `NODE_TYPE_NAME` matches `fn_decl.return_type.type`
  ```

### `test_Parser_FnDecl_Error_MissingReturnType`
- **Implementation Source**: `tests/test_parser_fn_decl.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort(source` is satisfied
  ```

### `test_Parser_FnDecl_Error_MissingParens`
- **Implementation Source**: `tests/test_parser_fn_decl.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func -> i32 {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort(source` is satisfied
  ```

### `test_Parser_NonEmptyFunctionBody`
- **Implementation Source**: `tests/test_parser_functions.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn main() -> i32 {
    const x: i32 = 42;
    if (x == 42) {
        return 0;
    }
    return 1;
}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `decl not equals null` is satisfied
  2. Assert that `NODE_FN_DECL` matches `decl.type`
  3. Validate that `fn_decl.return_type not equals null` is satisfied
  4. Assert that `NODE_TYPE_NAME` matches `fn_decl.return_type.type`
  5. Validate that `fn_decl.body not equals null` is satisfied
  6. Assert that `NODE_BLOCK_STMT` matches `fn_decl.body.type`
  7. Assert that `3` matches `body_block.statements.length`
  8. Assert that `NODE_VAR_DECL` matches `var_decl_stmt.type`
  9. Validate that `var_decl.is_const` is satisfied
  10. Assert that `42` matches `var_decl.initializer.as.integer_literal.value`
  11. Assert that `NODE_IF_STMT` matches `if_stmt_node.type`
  12. Assert that `NODE_BINARY_OP` matches `if_stmt.condition.type`
  13. Validate that `if_stmt.then_block not equals null` is satisfied
  14. Validate that `if_stmt.else_block equals null` is satisfied
  15. Assert that `NODE_RETURN_STMT` matches `return_stmt.type`
  16. Assert that `1` matches `return_stmt.as.return_stmt.expression.as.integer_literal.value`
  ```

### `test_Parser_VarDecl_InsertsSymbolCorrectly`
- **Implementation Source**: `tests/parser_symbol_integration_tests.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var my_var: i32 = 123;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `decl_node not equals null` is satisfied
  2. Validate that `found_symbol not equals null` is satisfied
  3. Assert that `SYMBOL_VARIABLE` matches `kind of found_symbol`
  4. Validate that `found_symbol.symbol_type not equals null` is satisfied
  5. Assert that `TYPE_I32` matches `found_symbol.kind of symbol_type`
  ```

### `test_Parser_VarDecl_DetectsDuplicateSymbol`
- **Implementation Source**: `tests/parser_symbol_integration_tests.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
{ var x: i32 = 1; var x: bool = true; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort(source` is satisfied
  ```

### `test_Parser_FnDecl_AndScopeManagement`
- **Implementation Source**: `tests/parser_symbol_integration_tests.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() -> void { var local: i32 = 1; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `1` matches `table.getCurrentScopeLevel`
  2. Validate that `decl_node not equals null` is satisfied
  3. Validate that `func_symbol not equals null` is satisfied
  4. Assert that `SYMBOL_FUNCTION` matches `kind of func_symbol`
  5. Validate that `local_symbol equals null` is satisfied
  ```

### `test_ASTNode_ForStmt`
- **Implementation Source**: `tests/test_ast_control_flow.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_FOR_STMT` matches `node.type`
  2. Validate that `node.as.for_stmt.iterable_expr not equals null` is satisfied
  3. Validate that `node.as.for_stmt.body not equals null` is satisfied
  ```

### `test_ASTNode_SwitchExpr`
- **Implementation Source**: `tests/test_ast_control_flow.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `NODE_SWITCH_EXPR` matches `node.type`
  2. Validate that `node.as.switch_expr.expression not equals null` is satisfied
  3. Validate that `node.as.switch_expr.prongs equals null` is satisfied
  ```

### `test_Parser_IfStatement_Simple`
- **Implementation Source**: `tests/test_parser_if_statement.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
if (1) {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `if_stmt_node not equals null` is satisfied
  2. Assert that `NODE_IF_STMT` matches `if_stmt_node.type`
  3. Validate that `if_stmt.condition not equals null` is satisfied
  4. Assert that `NODE_INTEGER_LITERAL` matches `if_stmt.condition.type`
  5. Validate that `if_stmt.then_block not equals null` is satisfied
  6. Assert that `NODE_BLOCK_STMT` matches `if_stmt.then_block.type`
  7. Validate that `if_stmt.else_block equals null` is satisfied
  ```

### `test_Parser_IfStatement_WithElse`
- **Implementation Source**: `tests/test_parser_if_statement.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
if (1) {} else {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `if_stmt_node not equals null` is satisfied
  2. Assert that `NODE_IF_STMT` matches `if_stmt_node.type`
  3. Validate that `if_stmt.condition not equals null` is satisfied
  4. Assert that `NODE_INTEGER_LITERAL` matches `if_stmt.condition.type`
  5. Validate that `if_stmt.then_block not equals null` is satisfied
  6. Assert that `NODE_BLOCK_STMT` matches `if_stmt.then_block.type`
  7. Validate that `if_stmt.else_block not equals null` is satisfied
  8. Assert that `NODE_BLOCK_STMT` matches `if_stmt.else_block.type`
  ```

### `test_Parser_ParseEmptyBlock`
- **Implementation Source**: `tests/test_parser_block.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_BLOCK_STMT` matches `node.type`
  3. Assert that `0` matches `node.as.block_stmt.statements.length`
  ```

### `test_Parser_ParseBlockWithEmptyStatement`
- **Implementation Source**: `tests/test_parser_block.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_BLOCK_STMT` matches `node.type`
  3. Assert that `1` matches `node.as.block_stmt.statements.length`
  4. Assert that `NODE_EMPTY_STMT` matches `stmt.type`
  ```

### `test_Parser_ParseBlockWithMultipleEmptyStatements`
- **Implementation Source**: `tests/test_parser_block.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_BLOCK_STMT` matches `node.type`
  3. Assert that `2` matches `node.as.block_stmt.statements.length`
  4. Assert that `NODE_EMPTY_STMT` matches `stmt1.type`
  5. Assert that `NODE_EMPTY_STMT` matches `stmt2.type`
  ```

### `test_Parser_ParseBlockWithNestedEmptyBlock`
- **Implementation Source**: `tests/test_parser_block.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_BLOCK_STMT` matches `node.type`
  3. Assert that `1` matches `node.as.block_stmt.statements.length`
  4. Assert that `NODE_BLOCK_STMT` matches `nested_block.type`
  5. Assert that `0` matches `nested_block.as.block_stmt.statements.length`
  ```

### `test_Parser_ParseBlockWithMultipleNestedEmptyBlocks`
- **Implementation Source**: `tests/test_parser_block.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_BLOCK_STMT` matches `node.type`
  3. Assert that `2` matches `node.as.block_stmt.statements.length`
  4. Assert that `NODE_BLOCK_STMT` matches `nested_block1.type`
  5. Assert that `0` matches `nested_block1.as.block_stmt.statements.length`
  6. Assert that `NODE_BLOCK_STMT` matches `nested_block2.type`
  7. Assert that `0` matches `nested_block2.as.block_stmt.statements.length`
  ```

### `test_Parser_ParseBlockWithNestedBlockAndEmptyStatement`
- **Implementation Source**: `tests/test_parser_block.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_BLOCK_STMT` matches `node.type`
  3. Assert that `2` matches `node.as.block_stmt.statements.length`
  4. Assert that `NODE_BLOCK_STMT` matches `nested_block.type`
  5. Assert that `0` matches `nested_block.as.block_stmt.statements.length`
  6. Assert that `NODE_EMPTY_STMT` matches `empty_stmt.type`
  ```

### `test_Parser_ErrDeferStatement_Simple`
- **Implementation Source**: `tests/test_parser_errdefer.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
errdefer {; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `stmt_node not equals null` is satisfied
  2. Assert that `NODE_ERRDEFER_STMT` matches `stmt_node.type`
  3. Validate that `errdefer_stmt.statement not equals null` is satisfied
  4. Assert that `NODE_BLOCK_STMT` matches `errdefer_stmt.statement.type`
  5. Validate that `body.statements not equals null` is satisfied
  6. Assert that `1` matches `body.statements.length`
  7. Assert that `NODE_EMPTY_STMT` matches `*body.statements)[0].type`
  8. Validate that `parser.is_at_end` is satisfied
  ```

### `test_Parser_ComptimeBlock_Valid`
- **Implementation Source**: `tests/test_parser_comptime.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
comptime { 123 }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `stmt not equals null` is satisfied
  2. Assert that `NODE_COMPTIME_BLOCK` matches `stmt.type`
  3. Validate that `comptime_block.expression not equals null` is satisfied
  4. Assert that `NODE_INTEGER_LITERAL` matches `comptime_block.expression.type`
  5. Assert that `123` matches `comptime_block.expression.as.integer_literal.value`
  ```

### `test_Parser_NestedBlocks_AndShadowing`
- **Implementation Source**: `tests/parser_symbol_integration_tests.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
{ var x: i32 = 1; { var x: bool = false; } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `block_node not equals null` is satisfied
  2. Validate that `symbol_after equals null` is satisfied
  ```

### `test_Parser_SymbolDoesNotLeakFromInnerScope`
- **Implementation Source**: `tests/parser_symbol_integration_tests.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
{ var a: i32 = 1; { var b: bool = true; } }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `block_node not equals null` is satisfied
  2. Validate that `table.lookup("a"` is satisfied
  3. Validate that `table.lookup("b"` is satisfied
  ```

### `test_Parser_Error_OnUnexpectedToken`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort(source` is satisfied
  ```

### `test_Parser_Error_OnMissingColon`
- **Implementation Source**: `tests/test_parser_errors.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort(source` is satisfied
  ```

### `test_Parser_IfStatement_Error_MissingLParen`
- **Implementation Source**: `tests/test_parser_if_statement.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
if 1) {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort("if 1` is satisfied
  ```

### `test_Parser_IfStatement_Error_MissingRParen`
- **Implementation Source**: `tests/test_parser_if_statement.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
if (1 {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort("if (1 {}"` is satisfied
  ```

### `test_Parser_IfStatement_Error_MissingThenBlock`
- **Implementation Source**: `tests/test_parser_if_statement.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
if (1)
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort("if (1` is satisfied
  ```

### `test_Parser_IfStatement_Error_MissingElseBlock`
- **Implementation Source**: `tests/test_parser_if_statement.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
if (1) {} else
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort("if (1` is satisfied
  ```

### `test_Parser_BinaryExpr_Error_MissingRHS`
- **Implementation Source**: `tests/test_parser_expressions.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_TryExpr_InvalidSyntax`
- **Implementation Source**: `tests/test_parser_try_expr.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort("try;"` is satisfied
  ```

### `test_Parser_CatchExpression_Error_MissingElseExpr`
- **Implementation Source**: `tests/test_parser_catch_expr.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_CatchExpression_Error_IncompletePayload`
- **Implementation Source**: `tests/test_parser_catch_expr.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch |err
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_CatchExpression_Error_MissingPipe`
- **Implementation Source**: `tests/test_parser_catch_expr.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
a catch |err|
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_ErrDeferStatement_Error_MissingBlock`
- **Implementation Source**: `tests/test_parser_errdefer.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort("errdefer;"` is satisfied
  2. Validate that `expect_statement_parser_abort("errdefer 123;"` is satisfied
  ```

### `test_Parser_ComptimeBlock_Error_MissingExpression`
- **Implementation Source**: `tests/test_parser_comptime.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort("comptime { }"` is satisfied
  ```

### `test_Parser_ComptimeBlock_Error_MissingOpeningBrace`
- **Implementation Source**: `tests/test_parser_comptime.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  ```

### `test_Parser_ComptimeBlock_Error_MissingClosingBrace`
- **Implementation Source**: `tests/test_parser_comptime.cpp`
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_parser_abort("comptime { 123"` is satisfied
  ```

### `test_Parser_AbortOnAllocationFailure`
- **Implementation Source**: `tests/test_parser_memory.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    ASSERT_TRUE(did_abort);
    if (!did_abort) {
        printf(
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `did_abort` is satisfied
  ```

### `test_Parser_TokenStreamLifetimeIsIndependentOfParserObject`
- **Implementation Source**: `tests/test_parser_lifecycle.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  ```

### `test_Parser_MalformedStream_MissingEOF`
- **Implementation Source**: `tests/test_parser_lifecycle.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
);
    tokens[0].location = SourceLocation();
    tokens[1].type = TOKEN_SEMICOLON;
    tokens[1].location = SourceLocation();

    SymbolTable symbol_table(arena);
    // Actually, it's easier to use the existing infrastructure if possible,
    // but the TokenSupplier always adds EOF.
    // Let's use the Parser constructor directly.

    SourceManager source_manager(arena);
    ErrorHandler eh(source_manager, arena);
    ErrorSetCatalogue catalogue(arena);
    GenericCatalogue generic_catalogue(arena);
    TypeInterner type_interner(arena);

    Parser parser(tokens, 2, &arena, &symbol_table, &eh, &catalogue, &generic_catalogue, &type_interner, &interner,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Ensure that `parser.is_at_end` is false
  2. Validate that `parser.is_at_end` is satisfied
  3. Validate that `eh.hasErrors` is satisfied
  4. Assert that `TOKEN_EOF` matches `parser.peek().type`
  ```

### `test_ParserIntegration_VarDeclWithBinaryExpr`
- **Implementation Source**: `tests/test_parser_integration.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 = 10 + 20;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Validate that `node.type equals NODE_VAR_DECL` is satisfied
  3. Validate that `var_decl not equals null` is satisfied
  4. Validate that `var_decl.is_mut` is satisfied
  5. Validate that `var_decl.type.type equals NODE_TYPE_NAME` is satisfied
  6. Validate that `initializer not equals null` is satisfied
  7. Validate that `initializer.type equals NODE_BINARY_OP` is satisfied
  8. Validate that `bin_op.op equals TOKEN_PLUS` is satisfied
  9. Validate that `left not equals null` is satisfied
  10. Validate that `right not equals null` is satisfied
  11. Validate that `left.type equals NODE_INTEGER_LITERAL` is satisfied
  12. Validate that `right.type equals NODE_INTEGER_LITERAL` is satisfied
  13. Assert that `10` matches `left.as.integer_literal.value`
  14. Assert that `20` matches `right.as.integer_literal.value`
  ```

### `test_ParserIntegration_IfWithComplexCondition`
- **Implementation Source**: `tests/test_parser_integration.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
if (a and (b or c)) {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Validate that `node.type equals NODE_IF_STMT` is satisfied
  3. Validate that `if_stmt not equals null` is satisfied
  4. Validate that `if_stmt.then_block not equals null` is satisfied
  5. Validate that `if_stmt.else_block equals null` is satisfied
  6. Validate that `condition not equals null` is satisfied
  7. Validate that `condition.type equals NODE_BINARY_OP` is satisfied
  8. Validate that `and_op.op equals TOKEN_AND` is satisfied
  9. Validate that `and_left not equals null` is satisfied
  10. Validate that `and_left.type equals NODE_IDENTIFIER` is satisfied
  11. Validate that `and_right not equals null` is satisfied
  12. Validate that `and_right.type equals NODE_BINARY_OP` is satisfied
  13. Validate that `or_op.op equals TOKEN_OR` is satisfied
  14. Validate that `or_left not equals null` is satisfied
  15. Validate that `or_right not equals null` is satisfied
  16. Validate that `or_left.type equals NODE_IDENTIFIER` is satisfied
  17. Validate that `or_right.type equals NODE_IDENTIFIER` is satisfied
  ```

### `test_ParserIntegration_WhileWithFunctionCall`
- **Implementation Source**: `tests/test_parser_integration.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
while (should_continue()) {}
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Validate that `node.type equals NODE_WHILE_STMT` is satisfied
  3. Validate that `while_stmt.body not equals null` is satisfied
  4. Validate that `while_stmt.body.type equals NODE_BLOCK_STMT` is satisfied
  5. Validate that `condition not equals null` is satisfied
  6. Validate that `condition.type equals NODE_FUNCTION_CALL` is satisfied
  7. Validate that `call_node.callee not equals null` is satisfied
  8. Validate that `call_node.callee.type equals NODE_IDENTIFIER` is satisfied
  9. Validate that `call_node.args not equals null` is satisfied
  10. Assert that `0` matches `call_node.args.length`
  ```

### `test_ParserBug_LogicalOperatorSymbol`
- **Implementation Source**: `tests/test_parser_bug.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: bool = a and b;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Validate that `initializer not equals null` is satisfied
  3. Validate that `initializer.type equals NODE_BINARY_OP` is satisfied
  4. Validate that `bin_op.op equals TOKEN_AND` is satisfied
  ```

### `test_Parser_RecursionLimit`
- **Implementation Source**: `tests/test_parser_recursion.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 =
  ```
  ```zig
);
    for (int i = 0; i < 1100; ++i) {
        strcat(source,
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Confirm Parser correctly identifies and rejects syntax error
  2. Validate that `expect_statement_parser_abort(source` is satisfied
  ```

### `test_Parser_RecursionLimit_Unary`
- **Implementation Source**: `tests/test_parser_recursion.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
var x: i32 =
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort(source` is satisfied
  ```

### `test_Parser_RecursionLimit_Binary`
- **Implementation Source**: `tests/test_parser_recursion.cpp`
- **Zig Source Input (Test Case Context)**:
  ```zig
fn foo() void { var a: i32 = 0;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `expect_statement_parser_abort(source` is satisfied
  ```

### `test_Parser_CopyIsSafeAndDoesNotDoubleFree`
- **Implementation Source**: `tests/test_parser_lifecycle.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
const x: i32 = 42;
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Assert that `TOKEN_IDENTIFIER` matches `p1.peek().type`
  2. Assert that `TOKEN_COLON` matches `p2.peek().type`
  3. Assert that `TOKEN_IDENTIFIER` matches `p3.peek().type`
  ```

### `test_Parser_Bugfix_HandlesExpressionStatement`
- **Implementation Source**: `tests/parser_bug_fixes.cpp`
- **Sub-system Coverage**: Syntactic Analysis
- **Zig Source Input (Test Case Context)**:
  ```zig
fn my_func() void { 42; }
  ```
- **Verification Logic (Behavioral Specification)**:
  ```pseudocode
  1. Validate that `node not equals null` is satisfied
  2. Assert that `NODE_BLOCK_STMT` matches `node.type`
  3. Assert that `1` matches `node.as.block_stmt.statements.length`
  4. Assert that `NODE_FN_DECL` matches `fn_decl.type`
  5. Assert that `NODE_BLOCK_STMT` matches `fn_body.type`
  6. Assert that `1` matches `fn_body.as.block_stmt.statements.length`
  7. Assert that `NODE_EXPRESSION_STMT` matches `expr_stmt.type`
  8. Assert that `NODE_INTEGER_LITERAL` matches `literal.type`
  9. Assert that `42` matches `literal.as.integer_literal.value`
  ```
