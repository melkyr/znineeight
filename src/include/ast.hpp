#ifndef AST_HPP
#define AST_HPP

#include "common.hpp"
#include "lexer.hpp" // For SourceLocation and TokenType
#include "memory.hpp" // For DynamicArray

// Forward-declare the main ASTNode struct so it can be used in the specific node structs.
struct ASTNode;

/**
 * @enum NodeType
 * @brief Defines the type of each node in the Abstract Syntax Tree.
 *
 * This enum is used in the `ASTNode` struct to identify what kind of language construct
 * the node represents.
 */
enum NodeType {
    // ~~~~~~~~~~~~~~~~~~~~~~ Expressions ~~~~~~~~~~~~~~~~~~~~~~
    NODE_UNARY_OP,        ///< A unary operation (e.g., `-x`, `!y`).
    NODE_BINARY_OP,       ///< A binary operation (e.g., `a + b`).

    // ~~~~~~~~~~~~~~~~~~~~~~~ Literals ~~~~~~~~~~~~~~~~~~~~~~~~
    NODE_INTEGER_LITERAL, ///< An integer literal (e.g., `123`, `0xFF`).
    NODE_FLOAT_LITERAL,   ///< A floating-point literal (e.g., `3.14`).
    NODE_CHAR_LITERAL,    ///< A character literal (e.g., `'a'`).
    NODE_STRING_LITERAL,  ///< A string literal (e.g., `"hello"`).
    NODE_IDENTIFIER,      ///< An identifier (e.g., a variable name `my_var`).

    // ~~~~~~~~~~~~~~~~~~~~~~ Statements ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_BLOCK_STMT,      ///< A block of statements enclosed in `{}`.
    NODE_IF_STMT,         ///< An if-else statement.
    NODE_WHILE_STMT,      ///< A while loop statement.
    NODE_RETURN_STMT,     ///< A return statement.
    NODE_DEFER_STMT,      ///< A defer statement.

    // ~~~~~~~~~~~~~~~~~~~~ Declarations ~~~~~~~~~~~~~~~~~~~~~~~
    NODE_VAR_DECL,        ///< A variable or constant declaration.
    NODE_FN_DECL          ///< A function declaration.
};

// --- Forward declarations for node-specific structs ---
struct ASTVarDeclNode;
struct ASTFnDeclNode;
struct ASTParamDeclNode;


// --- Node-specific data structs ---
// These structs are stored within the ASTNode's union.

/**
 * @struct ASTBinaryOpNode
 * @brief Represents a binary operation.
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
 * @brief Represents a unary operation.
 * @var ASTUnaryOpNode::operand The operand.
 * @var ASTUnaryOpNode::op The token representing the operator (e.g., TOKEN_MINUS).
 */
struct ASTUnaryOpNode {
    ASTNode* operand;
    TokenType op;
};

/**
 * @struct ASTIntegerLiteralNode
 * @brief Represents an integer literal.
 * @var ASTIntegerLiteralNode::value The 64-bit integer value.
 */
struct ASTIntegerLiteralNode {
    i64 value;
};

/**
 * @struct ASTFloatLiteralNode
 * @brief Represents a floating-point literal.
 * @var ASTFloatLiteralNode::value The double-precision float value.
 */
struct ASTFloatLiteralNode {
    double value;
};

/**
 * @struct ASTCharLiteralNode
 * @brief Represents a character literal.
 * @var ASTCharLiteralNode::value The character value.
 */
struct ASTCharLiteralNode {
    char value;
};

/**
 * @struct ASTStringLiteralNode
 * @brief Represents a string literal.
 * @var ASTStringLiteralNode::value A pointer to the interned string.
 */
struct ASTStringLiteralNode {
    const char* value;
};

/**
 * @struct ASTIdentifierNode
 * @brief Represents an identifier.
 * @var ASTIdentifierNode::name A pointer to the interned string for the identifier's name.
 */
struct ASTIdentifierNode {
    const char* name;
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

// --- Declaration Nodes ---

/**
 * @struct ASTParamDeclNode
 * @brief Represents a single parameter in a function declaration.
 * @var ASTParamDeclNode::name The name of the parameter (interned string).
 * @var ASTParamDeclNode::type A pointer to an ASTNode representing the parameter's type.
 */
struct ASTParamDeclNode {
    const char* name;
    ASTNode* type;
};

/**
 * @struct ASTVarDeclNode
 * @brief Represents a variable or constant declaration (`var` or `const`).
 * @var ASTVarDeclNode::name The name of the variable (interned string).
 * @var ASTVarDeclNode::type A pointer to an ASTNode for the declared type (can be NULL for inferred types).
 * @var ASTVarDeclNode::initializer A pointer to the expression used to initialize the variable.
 * @var ASTVarDeclNode::is_const True if the declaration is `const`.
 * @var ASTVarDeclNode::is_mut True if the declaration is `var` (mutable).
 */
struct ASTVarDeclNode {
    const char* name;
    ASTNode* type; // Can be NULL
    ASTNode* initializer;
    bool is_const;
    bool is_mut;
};

/**
 * @struct ASTFnDeclNode
 * @brief Represents a function declaration. This is a larger struct and is allocated
 * separately; the ASTNode union holds a pointer to it.
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
 * All ASTNodes should be allocated using the ArenaAllocator to ensure they are freed
 * all at once after compilation is finished.
 */
struct ASTNode {
    NodeType type;
    SourceLocation loc;

    union {
        // Expressions
        ASTBinaryOpNode binary_op;
        ASTUnaryOpNode unary_op;

        // Literals
        ASTIntegerLiteralNode integer_literal;
        ASTFloatLiteralNode float_literal;
        ASTCharLiteralNode char_literal;
        ASTStringLiteralNode string_literal;
        ASTIdentifierNode identifier;

        // Statements
        ASTBlockStmtNode block_stmt;
        ASTIfStmtNode if_stmt;
        ASTWhileStmtNode while_stmt;
        ASTReturnStmtNode return_stmt;
        ASTDeferStmtNode defer_stmt;

        // Declarations
        ASTVarDeclNode var_decl;
        ASTFnDeclNode* fn_decl; // Pointer for out-of-line allocation
    } as;
};

#endif // AST_HPP
