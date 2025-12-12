#ifndef AST_HPP
#define AST_HPP

#include "common.hpp"
#include "lexer.hpp" // For SourceLocation and TokenType

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
    NODE_IDENTIFIER       ///< An identifier (e.g., a variable name `my_var`).
};

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
        ASTBinaryOpNode binary_op;
        ASTUnaryOpNode unary_op;
        ASTIntegerLiteralNode integer_literal;
        ASTFloatLiteralNode float_literal;
        ASTCharLiteralNode char_literal;
        ASTStringLiteralNode string_literal;
        ASTIdentifierNode identifier;
    } as;
};

#endif // AST_HPP
