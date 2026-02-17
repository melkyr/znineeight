#ifndef AST_HPP
#define AST_HPP

#include "common.hpp"
#include "lexer.hpp" // For SourceLocation and TokenType
#include "memory.hpp" // For DynamicArray

// Forward-declare the main ASTNode struct so it can be used in the specific node structs.
struct ASTNode;
struct Type;
struct Symbol;

/**
 * @enum NodeType
 * @brief Defines the type of each node in the Abstract Syntax Tree.
 *
 * This enum is used in the `ASTNode` struct to identify what kind of language construct
 * the node represents.
 */
enum NodeType {
    // ~~~~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~~
    NODE_ASSIGNMENT,
    NODE_COMPOUND_ASSIGNMENT,
    NODE_UNARY_OP,        ///< A unary operation (e.g., `-x`, `!y`).
    NODE_BINARY_OP,       ///< A binary operation (e.g., `a + b`).
    NODE_FUNCTION_CALL,   ///< A function call expression (e.g., `foo()`).
    NODE_ARRAY_ACCESS,    ///< An array access expression (e.g., `arr[i]`).
    NODE_ARRAY_SLICE,     ///< An array slice expression (e.g., `arr[start..end]`).
    NODE_MEMBER_ACCESS,   ///< A member access expression (e.g., `s.field`).
    NODE_STRUCT_INITIALIZER, ///< A struct initializer (e.g., `S { .x = 1 }`).

    // ~~~~~~~~~~~~~~~~~~~~~~~ Literals ~~~~~~~~~~~~~~~~~~~~~~~~
    NODE_BOOL_LITERAL,    ///< A boolean literal (`true` or `false`).
    NODE_NULL_LITERAL,    ///< A `null` literal.
    NODE_UNDEFINED_LITERAL, ///< An `undefined` literal.
    NODE_INTEGER_LITERAL, ///< An integer literal (e.g., `123`, `0xFF`).
    NODE_FLOAT_LITERAL,   ///< A floating-point literal (e.g., `3.14`).
    NODE_CHAR_LITERAL,    ///< A character literal (e.g., `'a'`).
    NODE_STRING_LITERAL,  ///< A string literal (e.g., `"hello"`).
    NODE_IDENTIFIER,      ///< An identifier (e.g., a variable name `my_var`).

    // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_BLOCK_STMT,      ///< A block of statements enclosed in `{}`.
    NODE_EMPTY_STMT,      ///< An empty statement (`;`).
    NODE_IF_STMT,         ///< An if-else statement.
    NODE_WHILE_STMT,      ///< A while loop statement.
    NODE_BREAK_STMT,      ///< A break statement.
    NODE_CONTINUE_STMT,   ///< A continue statement.
    NODE_RETURN_STMT,     ///< A return statement.
    NODE_DEFER_STMT,      ///< A defer statement.
    NODE_FOR_STMT,        ///< A for loop statement.
    NODE_EXPRESSION_STMT, ///< A statement that consists of a single expression.
    NODE_PAREN_EXPR,      ///< A parenthesized expression (e.g., `(a + b)`).

    // ~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~
    NODE_SWITCH_EXPR,     ///< A switch expression.
    NODE_PTR_CAST,        ///< A pointer cast expression (@ptrCast).
    NODE_INT_CAST,        ///< An integer cast expression (@intCast).
    NODE_FLOAT_CAST,      ///< A floating-point cast expression (@floatCast).
    NODE_OFFSET_OF,       ///< A field offset expression (@offsetOf).

    // ~~~~~~~~~~~~~~~~~~~~ Declarations ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_VAR_DECL,        ///< A variable or constant declaration.
    NODE_PARAM_DECL,      ///< A function parameter declaration.
    NODE_FN_DECL,         ///< A function declaration.
    NODE_STRUCT_FIELD,    ///< A single field within a struct declaration.

    // ~~~~~~~~~~~~~~ Container Declarations ~~~~~~~~~~~~~~~~~
    NODE_STRUCT_DECL,     ///< A struct declaration.
    NODE_UNION_DECL,      ///< A union declaration.
    NODE_ENUM_DECL,       ///< An enum declaration.
    NODE_ERROR_SET_DEFINITION, ///< An error set definition (e.g., `error { A, B }`).
    NODE_ERROR_SET_MERGE,      ///< An error set merge (e.g., `E1 || E2`).

    // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_IMPORT_STMT,     ///< An @import statement.

    // ~~~~~~~~~~~~~~~~~~~ Type Expressions ~~~~~~~~~~~~~~~~~~~~
    NODE_TYPE_NAME,       ///< A type represented by a name (e.g., `i32`).
    NODE_POINTER_TYPE,    ///< A pointer type (e.g., `*u8`).
    NODE_ARRAY_TYPE,      ///< An array or slice type (e.g., `[8]u8`, `[]bool`).
    NODE_ERROR_UNION_TYPE, ///< An error union type (e.g., `!i32`).
    NODE_OPTIONAL_TYPE,    ///< An optional type (e.g., `?i32`).
    NODE_FUNCTION_TYPE,    ///< A function type (e.g., `fn(i32) void`).

    // ~~~~~~~~~~~~~~~~ Error Handling ~~~~~~~~~~~~~~~~~
    NODE_TRY_EXPR,        ///< A try expression.
    NODE_CATCH_EXPR,      ///< A catch expression.
    NODE_ORELSE_EXPR,     ///< An orelse expression.
    NODE_ERRDEFER_STMT,   ///< An errdefer statement.

    // ~~~~~~~~~~~~~~~~ Async Operations ~~~~~~~~~~~~~~~~~
    NODE_ASYNC_EXPR,      ///< An async function call.
    NODE_AWAIT_EXPR,      ///< An await expression.

    // ~~~~~~~~~~~~~~~~ Compile-Time Operations ~~~~~~~~~~~~~~~~~
    NODE_COMPTIME_BLOCK   ///< A comptime block.
};

// --- Forward declarations for node-specific structs ---
struct ASTAssignmentNode;
struct ASTCompoundAssignmentNode;
struct ASTBinaryOpNode;
struct ASTUnaryOpNode;
struct ASTBoolLiteralNode;
struct ASTIntegerLiteralNode;
struct ASTFloatLiteralNode;
struct ASTCharLiteralNode;
struct ASTStringLiteralNode;
struct ASTIdentifierNode;
struct ASTBlockStmtNode;
struct ASTEmptyStmtNode;
struct ASTIfStmtNode;
struct ASTWhileStmtNode;
struct ASTBreakStmtNode;
struct ASTContinueStmtNode;
struct ASTReturnStmtNode;
struct ASTDeferStmtNode;
struct ASTForStmtNode;
struct ASTExpressionStmtNode;
struct ASTParenExprNode;
struct ASTSwitchExprNode;
struct ASTSwitchProngNode;
struct ASTVarDeclNode;
struct ASTFnDeclNode;
struct ASTParamDeclNode;
struct ASTStructFieldNode;
struct ASTStructDeclNode;
struct ASTUnionDeclNode;
struct ASTEnumDeclNode;
struct ASTErrorSetDefinitionNode;
struct ASTErrorSetMergeNode;
struct ASTImportStmtNode;
struct ASTTypeNameNode;
struct ASTPointerTypeNode;
struct ASTArrayTypeNode;
struct ASTErrorUnionTypeNode;
struct ASTOptionalTypeNode;
struct ASTFunctionTypeNode;
struct ASTTryExprNode;
struct ASTCatchExprNode;
struct ASTOrelseExprNode;
struct ASTErrDeferStmtNode;
struct ASTAsyncExprNode;
struct ASTAwaitExprNode;
struct ASTComptimeBlockNode;
struct ASTPtrCastNode;
struct ASTNumericCastNode;
struct ASTOffsetOfNode;
struct ASTFunctionCallNode;
struct ASTArrayAccessNode;
struct ASTArraySliceNode;
struct ASTMemberAccessNode;
struct ASTStructInitializerNode;
struct ASTNamedInitializer;


// --- Node-specific data structs ---
// These structs are stored within the ASTNode's union.

/**
 * @struct ASTAssignmentNode
 * @brief Represents a simple assignment expression (e.g., `x = y`).
 * @var ASTAssignmentNode::lvalue The left-hand side of the assignment.
 * @var ASTAssignmentNode::rvalue The right-hand side of the assignment.
 */
struct ASTAssignmentNode {
    ASTNode* lvalue;
    ASTNode* rvalue;
};

/**
 * @struct ASTMemberAccessNode
 * @brief Represents a member access expression (e.g., `s.field`).
 * @var ASTMemberAccessNode::base The expression being accessed.
 * @var ASTMemberAccessNode::field_name The name of the field (interned string).
 * @var ASTMemberAccessNode::symbol The resolved symbol (for module access).
 */
struct ASTMemberAccessNode {
    ASTNode* base;
    const char* field_name;
    Symbol* symbol;
};

/**
 * @struct ASTNamedInitializer
 * @brief Represents a single named field initializer in a struct initializer.
 * @var ASTNamedInitializer::field_name The name of the field (interned string).
 * @var ASTNamedInitializer::value The initializer expression.
 */
struct ASTNamedInitializer {
    const char* field_name;
    ASTNode* value;
    SourceLocation loc;
};

/**
 * @struct ASTStructInitializerNode
 * @brief Represents a struct initializer (e.g., `S { .x = 1, .y = 2 }`).
 * @var ASTStructInitializerNode::type_expr The type expression of the struct being initialized.
 * @var ASTStructInitializerNode::fields A dynamic array of pointers to the named field initializers.
 */
struct ASTStructInitializerNode {
    ASTNode* type_expr;
    DynamicArray<ASTNamedInitializer*>* fields;
};

/**
 * @struct ASTCompoundAssignmentNode
 * @brief Represents a compound assignment expression (e.g., `x += y`).
 * @var ASTCompoundAssignmentNode::lvalue The left-hand side of the assignment.
 * @var ASTCompoundAssignmentNode::rvalue The right-hand side of the assignment.
 * @var ASTCompoundAssignmentNode::op The token representing the operator (e.g., TOKEN_PLUS_EQUAL).
 */
struct ASTCompoundAssignmentNode {
    ASTNode* lvalue;
    ASTNode* rvalue;
    TokenType op;
};

/**
 * @struct ASTBinaryOpNode
 * @brief Represents a binary operation (e.g., `a + b`).
 * @var ASTBinaryOpNode::left The left-hand side operand.
 * @var ASTBinaryOpNode::right The right-hand side operand.
 * @var ASTBinaryOpNode::op The token representing the operator (e.g., TOKEN_PLUS).
 */
struct ASTBinaryOpNode {
    ASTNode* left;
    ASTNode* right;
    TokenType op;
};

/**
 * @struct ASTUnaryOpNode
 * @brief Represents a unary operation (e.g., `-x`, `!false`).
 * @var ASTUnaryOpNode::operand The operand.
 * @var ASTUnaryOpNode::op The token representing the operator (e.g., TOKEN_MINUS).
 */
struct ASTUnaryOpNode {
    ASTNode* operand;
    TokenType op;
};

/**
 * @struct ASTBoolLiteralNode
 * @brief Represents a boolean literal (`true` or `false`).
 * @var ASTBoolLiteralNode::value The boolean value.
 */
struct ASTBoolLiteralNode {
    bool value;
};

/**
 * @struct ASTIntegerLiteralNode
 * @brief Represents an integer literal (e.g., `42`, `0xFF`).
 * @var ASTIntegerLiteralNode::value The 64-bit integer value.
 */
struct ASTIntegerLiteralNode {
    u64 value;
    bool is_unsigned;
    bool is_long;
    Type* resolved_type;
    const char* original_name; // For enum member preservation
};

/**
 * @struct ASTFloatLiteralNode
 * @brief Represents a floating-point literal (e.g., `3.14`).
 * @var ASTFloatLiteralNode::value The double-precision float value.
 */
struct ASTFloatLiteralNode {
    double value;
    Type* resolved_type;
};

/**
 * @struct ASTCharLiteralNode
 * @brief Represents a character literal (e.g., `'z'`).
 * @var ASTCharLiteralNode::value The character value.
 */
struct ASTCharLiteralNode {
    char value;
};

/**
 * @struct ASTStringLiteralNode
 * @brief Represents a string literal (e.g., `"hello"`).
 * @var ASTStringLiteralNode::value A pointer to the interned string.
 */
struct ASTStringLiteralNode {
    const char* value;
};

/**
 * @struct ASTIdentifierNode
 * @brief Represents an identifier (e.g., `my_var`).
 * @var ASTIdentifierNode::name A pointer to the interned string for the identifier's name.
 */
struct ASTIdentifierNode {
    const char* name;
    Symbol* symbol;
};

/**
 * @struct ASTFunctionCallNode
 * @brief Represents a function call expression (e.g., `my_func(arg1, arg2)`).
 * @var ASTFunctionCallNode::callee The expression being called, typically an identifier.
 * @var ASTFunctionCallNode::args A dynamic array of pointers to the argument expressions.
 */
struct ASTFunctionCallNode {
    ASTNode* callee;
    DynamicArray<ASTNode*>* args;
};

/**
 * @struct ASTArrayAccessNode
 * @brief Represents an array or slice access expression (e.g., `my_array[index]`).
 * @var ASTArrayAccessNode::array The expression being indexed.
 * @var ASTArrayAccessNode::index The index expression.
 */
struct ASTArrayAccessNode {
    ASTNode* array;
    ASTNode* index;
};

/**
 * @struct ASTArraySliceNode
 * @brief Represents an array or slice expression (e.g., `my_array[start..end]`).
 * @var ASTArraySliceNode::array The expression being sliced.
 * @var ASTArraySliceNode::start The start index expression (can be NULL).
 * @var ASTArraySliceNode::end The end index expression (can be NULL).
 */
struct ASTArraySliceNode {
    ASTNode* array;
    ASTNode* start; // Can be NULL
    ASTNode* end;   // Can be NULL
};

/**
 * @struct ASTBlockStmtNode
 * @brief Represents a block of statements enclosed in braces `{}`.
 * @var ASTBlockStmtNode::statements A pointer to a dynamic array of pointers to the statements in the block.
 */
struct ASTBlockStmtNode {
    DynamicArray<ASTNode*>* statements;
};

/**
 * @struct ASTEmptyStmtNode
 * @brief Represents an empty statement, which is just a semicolon.
 */
struct ASTEmptyStmtNode {
    // This node has no data.
};

/**
 * @struct ASTIfStmtNode
 * @brief Represents an if-else statement.
 * @var ASTIfStmtNode::condition The condition expression.
 * @var ASTIfStmtNode::then_block The statement block to execute if the condition is true.
 * @var ASTIfStmtNode::else_block The statement block to execute if the condition is false (can be NULL).
 */
struct ASTIfStmtNode {
    ASTNode* condition;
    ASTNode* then_block;
    ASTNode* else_block; // Can be NULL
};

/**
 * @struct ASTWhileStmtNode
 * @brief Represents a while loop.
 * @var ASTWhileStmtNode::condition The loop condition expression.
 * @var ASTWhileStmtNode::body The statement block to execute while the condition is true.
 */
struct ASTWhileStmtNode {
    ASTNode* condition;
    ASTNode* body;
};

/**
 * @struct ASTBreakStmtNode
 * @brief Represents a break statement.
 */
struct ASTBreakStmtNode {
    // No data needed.
};

/**
 * @struct ASTContinueStmtNode
 * @brief Represents a continue statement.
 */
struct ASTContinueStmtNode {
    // No data needed.
};

/**
 * @struct ASTReturnStmtNode
 * @brief Represents a return statement.
 * @var ASTReturnStmtNode::expression The expression to return (can be NULL for a void return).
 */
struct ASTReturnStmtNode {
    ASTNode* expression; // Can be NULL
};

/**
 * @struct ASTDeferStmtNode
 * @brief Represents a defer statement.
 * @var ASTDeferStmtNode::statement The statement to be executed at the end of the scope.
 */
struct ASTDeferStmtNode {
    ASTNode* statement;
};

/**
 * @struct ASTForStmtNode
 * @brief Represents a for loop statement.
 * @var ASTForStmtNode::iterable_expr The expression being iterated over.
 * @var ASTForStmtNode::item_name The name of the item capture variable.
 * @var ASTForStmtNode::index_name The optional name of the index capture variable (can be NULL).
 * @var ASTForStmtNode::body The block statement that is the loop's body.
 */
struct ASTForStmtNode {
    ASTNode* iterable_expr;
    const char* item_name;
    const char* index_name; // Can be NULL
    ASTNode* body;
};

/**
 * @struct ASTExpressionStmtNode
 * @brief Represents a statement that consists solely of an expression, like a function call.
 * @var ASTExpressionStmtNode::expression The expression that makes up the statement.
 */
struct ASTExpressionStmtNode {
    ASTNode* expression;
};

/**
 * @struct ASTParenExprNode
 * @brief Represents a parenthesized expression (e.g., `(expr)`).
 * @var ASTParenExprNode::expr The inner expression.
 */
struct ASTParenExprNode {
    ASTNode* expr;
};

/**
 * @struct ASTSwitchProngNode
 * @brief Represents a single prong in a switch expression (e.g., `case => ...`).
 * @var ASTSwitchProngNode::cases A dynamic array of case expressions for this prong.
 * @var ASTSwitchProngNode::is_else True if this is the `else` prong.
 * @var ASTSwitchProngNode::body The expression to execute for this prong.
 */
struct ASTSwitchProngNode {
    DynamicArray<ASTNode*>* cases;
    bool is_else;
    ASTNode* body;
};

/**
 * @struct ASTSwitchExprNode
 * @brief Represents a switch expression.
 * @var ASTSwitchExprNode::expression The expression whose value is being switched on.
 * @var ASTSwitchExprNode::prongs A dynamic array of pointers to the switch prongs.
 */
struct ASTSwitchExprNode {
    ASTNode* expression;
    DynamicArray<ASTSwitchProngNode*>* prongs;
};

// --- Error Handling Nodes ---

/**
 * @struct ASTTryExprNode
 * @brief Represents a `try` expression, which unwraps a result or propagates an error.
 * @var ASTTryExprNode::expression The expression that might return an error.
 */
struct ASTTryExprNode {
    ASTNode* expression;
};

/**
 * @struct ASTCatchExprNode
 * @brief Represents a `catch` expression, which handles a potential error from a payload.
 * @var ASTCatchExprNode::payload The expression being evaluated that may result in an error.
 * @var ASTCatchExprNode::error_name The optional name for the captured error (can be NULL).
 * @var ASTCatchExprNode::else_expr The expression to execute if the payload is an error.
 */
struct ASTCatchExprNode {
    ASTNode* payload;
    const char* error_name; // Can be NULL
    ASTNode* else_expr;
};

/**
 * @struct ASTOrelseExprNode
 * @brief Represents an `orelse` expression, providing a fallback value for an optional type.
 * @var ASTOrelseExprNode::payload The expression that may be null or optional.
 * @var ASTOrelseExprNode::else_expr The expression to evaluate if the payload is null/optional.
 */
struct ASTOrelseExprNode {
    ASTNode* payload;
    ASTNode* else_expr;
};

/**
 * @struct ASTErrDeferStmtNode
 * @brief Represents an `errdefer` statement.
 * @var ASTErrDeferStmtNode::statement The statement to be executed upon error-based scope exit.
 */
struct ASTErrDeferStmtNode {
    ASTNode* statement;
};

// --- Async Nodes ---

/**
 * @struct ASTAsyncExprNode
 * @brief Represents an `async` expression, which initiates an asynchronous operation.
 * @var ASTAsyncExprNode::expression The function call or expression being executed asynchronously.
 */
struct ASTAsyncExprNode {
    ASTNode* expression;
};

/**
 * @struct ASTAwaitExprNode
 * @brief Represents an `await` expression, which pauses execution until an async operation completes.
 * @var ASTAwaitExprNode::expression The async expression being awaited.
 */
struct ASTAwaitExprNode {
    ASTNode* expression;
};

// --- Comptime Nodes ---

/**
 * @struct ASTComptimeBlockNode
 * @brief Represents a `comptime` block, which contains an expression to be evaluated at compile-time.
 * @var ASTComptimeBlockNode::expression The expression inside the comptime block.
 */
struct ASTComptimeBlockNode {
    ASTNode* expression;
};

/**
 * @struct ASTPtrCastNode
 * @brief Represents an explicit pointer cast (@ptrCast).
 * @var ASTPtrCastNode::target_type The target pointer type expression.
 * @var ASTPtrCastNode::expr The expression being cast.
 */
struct ASTPtrCastNode {
    ASTNode* target_type;
    ASTNode* expr;
};

/**
 * @struct ASTNumericCastNode
 * @brief Represents an explicit numeric cast (@intCast, @floatCast).
 * @var ASTNumericCastNode::target_type The target numeric type expression.
 * @var ASTNumericCastNode::expr The expression being cast.
 */
struct ASTNumericCastNode {
    ASTNode* target_type;
    ASTNode* expr;
};

/**
 * @struct ASTOffsetOfNode
 * @brief Represents an explicit field offset expression (@offsetOf).
 * @var ASTOffsetOfNode::type_expr The aggregate type expression.
 * @var ASTOffsetOfNode::field_name The name of the field.
 */
struct ASTOffsetOfNode {
    ASTNode* type_expr;
    const char* field_name;
};


// --- Declaration Nodes ---

/**
 * @struct ASTParamDeclNode
 * @brief Represents a single parameter in a function declaration.
 * @var ASTParamDeclNode::name The name of the parameter (interned string).
 * @var ASTParamDeclNode::type A pointer to an ASTNode representing the parameter's type.
 * @var ASTParamDeclNode::is_comptime True if the parameter is marked 'comptime'.
 */
struct ASTParamDeclNode {
    const char* name;
    ASTNode* type;
    bool is_comptime;
    bool is_anytype;
    bool is_type_param;
    Symbol* symbol;
};

/**
 * @struct ASTVarDeclNode
 * @brief Represents a `var` or `const` declaration. Allocated out-of-line.
 * @var ASTVarDeclNode::name The name of the variable (interned string).
 * @var ASTVarDeclNode::type A pointer to an ASTNode for the declared type (can be NULL for inferred types).
 * @var ASTVarDeclNode::initializer A pointer to the expression used to initialize the variable.
 * @var ASTVarDeclNode::is_const True if the declaration is `const`.
 * @var ASTVarDeclNode::is_mut True if the declaration is `var` (mutable).
 */
struct ASTVarDeclNode {
    const char* name;
    SourceLocation name_loc;
    ASTNode* type; // Can be NULL
    ASTNode* initializer;
    bool is_const;
    bool is_mut;
    bool is_pub;
    bool is_extern;
    bool is_export;
    Symbol* symbol;
};

/**
 * @struct ASTFnDeclNode
 * @brief Represents a function declaration. Allocated out-of-line.
 * @var ASTFnDeclNode::name The name of the function (interned string).
 * @var ASTFnDeclNode::params A dynamic array of pointers to ASTParamDeclNode.
 * @var ASTFnDeclNode::return_type A pointer to an ASTNode for the return type (can be NULL).
 * @var ASTFnDeclNode::body A pointer to the block statement that is the function's body.
 */
struct ASTFnDeclNode {
    const char* name;
    DynamicArray<ASTParamDeclNode*>* params;
    ASTNode* return_type; // Can be NULL
    ASTNode* body;
    bool is_pub;
    bool is_extern;
    bool is_export;
};

// --- Container Declaration Nodes ---

/**
 * @struct ASTStructFieldNode
 * @brief Represents a single field within a struct declaration.
 * @var ASTStructFieldNode::name The name of the field (interned string).
 * @var ASTStructFieldNode::type A pointer to an ASTNode representing the field's type.
 */
struct ASTStructFieldNode {
    const char* name;
    SourceLocation name_loc;
    ASTNode* type;
};

/**
 * @struct ASTStructDeclNode
 * @brief Represents a `struct` declaration. Allocated out-of-line.
 * @var ASTStructDeclNode::fields A dynamic array of pointers to ASTVarDeclNode representing the struct fields.
 */
struct ASTStructDeclNode {
    DynamicArray<ASTNode*>* fields;
};

/**
 * @struct ASTUnionDeclNode
 * @brief Represents a `union` declaration. Allocated out-of-line.
 * @var ASTUnionDeclNode::fields A dynamic array of pointers to ASTVarDeclNode representing the union fields.
 */
struct ASTUnionDeclNode {
    DynamicArray<ASTNode*>* fields;
};

/**
 * @struct ASTEnumDeclNode
 * @brief Represents an `enum` declaration. Allocated out-of-line.
 * @var ASTEnumDeclNode::backing_type The optional explicit backing type for the enum (can be NULL).
 * @var ASTEnumDeclNode::fields A dynamic array of pointers to ASTVarDeclNode representing the enum fields, allowing for explicit values.
 */
struct ASTEnumDeclNode {
    ASTNode* backing_type; // Can be NULL
    DynamicArray<ASTNode*>* fields;
};

/**
 * @struct ASTErrorSetDefinitionNode
 * @brief Represents an error set definition (e.g., `error { A, B }`).
 * @var ASTErrorSetDefinitionNode::name The name of the error set (can be NULL if anonymous).
 * @var ASTErrorSetDefinitionNode::tags A dynamic array of interned strings representing the error tags.
 */
struct ASTErrorSetDefinitionNode {
    const char* name; // NULL for anonymous
    DynamicArray<const char*>* tags;
};

/**
 * @struct ASTErrorSetMergeNode
 * @brief Represents an error set merge (e.g., `E1 || E2`).
 * @var ASTErrorSetMergeNode::left The left-hand side of the merge.
 * @var ASTErrorSetMergeNode::right The right-hand side of the merge.
 */
struct ASTErrorSetMergeNode {
    ASTNode* left;
    ASTNode* right;
};

/**
 * @struct ASTImportStmtNode
 * @brief Represents an @import statement.
 * @var ASTImportStmtNode::module_name The name of the module being imported.
 */
struct ASTImportStmtNode {
    const char* module_name;
    struct Module* module_ptr;
};


// --- Type Expression Nodes ---

/**
 * @struct ASTTypeNameNode
 * @brief Represents a type specified by an identifier (e.g., `i32`, `MyStruct`).
 * @var ASTTypeNameNode::name The name of the type (interned string).
 */
struct ASTTypeNameNode {
    const char* name;
};

/**
 * @struct ASTPointerTypeNode
 * @brief Represents a pointer type (e.g., `*i32`).
 * @var ASTPointerTypeNode::base A pointer to the ASTNode for the type being pointed to.
 */
struct ASTPointerTypeNode {
    ASTNode* base;
    bool is_const;
    bool is_many;
};

/**
 * @struct ASTArrayTypeNode
 * @brief Represents an array or slice type (e.g., `[8]u8`, `[]const u8`).
 * @var ASTArrayTypeNode::element_type A pointer to the ASTNode for the element type.
 * @var ASTArrayTypeNode::size An expression for the array size (can be NULL for a slice).
 */
struct ASTArrayTypeNode {
    ASTNode* element_type;
    ASTNode* size; // Can be NULL for a slice
};

/**
 * @struct ASTErrorUnionTypeNode
 * @brief Represents an error union type (e.g., `!i32`).
 * @var ASTErrorUnionTypeNode::payload_type A pointer to the ASTNode for the payload type.
 */
struct ASTErrorUnionTypeNode {
    ASTNode* error_set; // NULL for inferred (!)
    ASTNode* payload_type;
    SourceLocation loc;
};

/**
 * @struct ASTOptionalTypeNode
 * @brief Represents an optional type (e.g., `?i32`).
 * @var ASTOptionalTypeNode::payload_type A pointer to the ASTNode for the payload type.
 * @var ASTOptionalTypeNode::loc The source location of the '?' operator.
 */
struct ASTOptionalTypeNode {
    ASTNode* payload_type;
    SourceLocation loc;
};

/**
 * @struct ASTFunctionTypeNode
 * @brief Represents a function type (e.g., `fn(i32, i32) void`).
 * @var ASTFunctionTypeNode::params A dynamic array of pointers to the parameter type expressions.
 * @var ASTFunctionTypeNode::return_type A pointer to the return type expression.
 */
struct ASTFunctionTypeNode {
    DynamicArray<ASTNode*>* params;
    ASTNode* return_type;
};

/**
 * @struct ASTNode
 * @brief The fundamental building block of the Abstract Syntax Tree.
 *
 * Each `ASTNode` represents a single construct in the source code. It contains a `type`
 * to identify the construct, a `loc` for error reporting, and a `union` holding the
 * specific data for that construct type. This union-based design is memory-efficient,
 * which is crucial for the target hardware.
 *
 * All ASTNodes should be allocated using the ArenaAllocator. For memory efficiency,
 * larger node types are stored as pointers in the union ("out-of-line" allocation).
 */
struct ASTNode {
    NodeType type;
    SourceLocation loc;
    Type* resolved_type;
    const char* module;

    union {
        // Expressions
        ASTAssignmentNode* assignment; // Out-of-line
        ASTCompoundAssignmentNode* compound_assignment; // Out-of-line
        ASTBinaryOpNode* binary_op; // Out-of-line
        ASTUnaryOpNode unary_op;
        ASTFunctionCallNode* function_call; // Out-of-line
        ASTArrayAccessNode* array_access; // Out-of-line
        ASTArraySliceNode* array_slice; // Out-of-line
        ASTMemberAccessNode* member_access; // Out-of-line
        ASTStructInitializerNode* struct_initializer; // Out-of-line

        // Literals
        ASTBoolLiteralNode bool_literal;
        ASTIntegerLiteralNode integer_literal;
        ASTFloatLiteralNode float_literal;
        ASTCharLiteralNode char_literal;
        ASTStringLiteralNode string_literal;
        ASTIdentifierNode identifier;

        // Statements
        ASTBlockStmtNode block_stmt;
        ASTEmptyStmtNode empty_stmt;
        ASTIfStmtNode* if_stmt; // Out-of-line
        ASTWhileStmtNode while_stmt;
        ASTBreakStmtNode break_stmt;
        ASTContinueStmtNode continue_stmt;
        ASTReturnStmtNode return_stmt;
        ASTDeferStmtNode defer_stmt;
        ASTForStmtNode* for_stmt; // Out-of-line
        ASTExpressionStmtNode expression_stmt;
        ASTParenExprNode paren_expr;

        // Expressions
        ASTSwitchExprNode* switch_expr; // Out-of-line
        ASTPtrCastNode* ptr_cast; // Out-of-line
        ASTNumericCastNode* numeric_cast; // Out-of-line
        ASTOffsetOfNode* offset_of; // Out-of-line

        // Error Handling
        ASTTryExprNode try_expr;
        ASTCatchExprNode* catch_expr; // Out-of-line
        ASTOrelseExprNode* orelse_expr; // Out-of-line
        ASTErrDeferStmtNode errdefer_stmt;

        // Async
        ASTAsyncExprNode async_expr;
        ASTAwaitExprNode await_expr;

        // Comptime
        ASTComptimeBlockNode comptime_block;

        // Declarations
        ASTVarDeclNode* var_decl; // Out-of-line
        ASTParamDeclNode param_decl;
        ASTFnDeclNode* fn_decl; // Out-of-line
        ASTStructFieldNode* struct_field; // Out-of-line
        ASTStructDeclNode* struct_decl; // Out-of-line
        ASTUnionDeclNode* union_decl; // Out-of-line
        ASTEnumDeclNode* enum_decl; // Out-of-line
        ASTErrorSetDefinitionNode* error_set_decl; // Out-of-line
        ASTErrorSetMergeNode* error_set_merge; // Out-of-line

        // Statements
        ASTImportStmtNode* import_stmt; // Out-of-line

        // Type Expressions
        ASTTypeNameNode type_name;
        ASTPointerTypeNode pointer_type;
        ASTArrayTypeNode array_type;
        ASTErrorUnionTypeNode* error_union_type; // Out-of-line
        ASTOptionalTypeNode* optional_type; // Out-of-line
        ASTFunctionTypeNode* function_type; // Out-of-line
    } as;
};

#endif // AST_HPP
