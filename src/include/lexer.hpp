#ifndef LEXER_HPP
#define LEXER_HPP

#include "common.hpp"
#include "source_manager.hpp"

/**
 * @file lexer.hpp
 * @brief Defines the token types and structures for the RetroZig lexer.
 *
 * This file contains the core definitions for the lexical analysis phase of
 * the compiler, including the TokenType enum which represents all possible
 * tokens in the Zig subset.
 */

/**
 * @enum TokenType
 * @brief Defines the different types of tokens that the lexer can produce.
 *
 * The enum is organized into logical groups for clarity:
 * - Control tokens
 * - Literals for identifiers and values
 * - Keywords for the language syntax
 * - Operators for expressions
 * - Delimiters for code structure
 */
enum TokenType {
    // Control Tokens
    TOKEN_EOF,              ///< End of the source file.

    // Literals
    TOKEN_IDENTIFIER,       ///< An identifier (e.g., variable name, function name).
    TOKEN_INTEGER_LITERAL,  ///< An integer literal (e.g., 123, 0xFF).
    TOKEN_STRING_LITERAL,   ///< A string literal (e.g., "hello").

    // Keywords
    TOKEN_FN,               ///< 'fn' keyword for function definitions.
    TOKEN_VAR,              ///< 'var' keyword for mutable variable declarations.
    TOKEN_CONST,            ///< 'const' keyword for immutable variable declarations.
    TOKEN_IF,               ///< 'if' keyword for conditional statements.
    TOKEN_ELSE,             ///< 'else' keyword for conditional statements.
    TOKEN_WHILE,            ///< 'while' keyword for loops.
    TOKEN_RETURN,           ///< 'return' keyword for function returns.
    TOKEN_DEFER,            ///< 'defer' keyword for scope-exit actions.

    // Operators
    TOKEN_PLUS,             ///< '+' operator.
    TOKEN_MINUS,            ///< '-' operator.
    TOKEN_STAR,             ///< '*' operator.
    TOKEN_SLASH,            ///< '/' operator.
    TOKEN_PERCENT,          ///< '%' operator.
    TOKEN_EQUAL,            ///< '=' operator (assignment).
    TOKEN_EQUAL_EQUAL,      ///< '==' operator (equality).
    TOKEN_BANG,             ///< '!' operator (logical not).
    TOKEN_BANG_EQUAL,       ///< '!=' operator (inequality).
    TOKEN_LESS,             ///< '<' operator.
    TOKEN_LESS_EQUAL,       ///< '<=' operator.
    TOKEN_GREATER,          ///< '>' operator.
    TOKEN_GREATER_EQUAL,    ///< '>=' operator.

    // Delimiters
    TOKEN_LPAREN,           ///< '(' - Left parenthesis.
    TOKEN_RPAREN,           ///< ')' - Right parenthesis.
    TOKEN_LBRACE,           ///< '{' - Left brace.
    TOKEN_RBRACE,           ///< '}' - Right brace.
    TOKEN_LBRACKET,         ///< '[' - Left bracket.
    TOKEN_RBRACKET,         ///< ']' - Right bracket.
    TOKEN_SEMICOLON,        ///< ';' - Semicolon.
    TOKEN_COLON,            ///< ':' - Colon.
};

/**
 * @struct Token
 * @brief Represents a single token produced by the lexer.
 *
 * A token is the smallest unit of meaning in the source code. It consists of
 * a type, its location in the source file, and an optional value for literals.
 */
struct Token {
    /** @brief The type of the token, as defined by the TokenType enum. */
    TokenType type;

    /** @brief The location (file, line, column) where the token was found. */
    SourceLocation location;

    /**
     * @union Value
     * @brief Stores the literal value of the token, if applicable.
     *
     * This union provides storage for different kinds of literal values.
     * The active member depends on the token's type:
     * - `identifier`: for TOKEN_IDENTIFIER (pointer to interned string)
     * - `integer`: for TOKEN_INTEGER_LITERAL
     * - `floating_point`: for potential future floating-point tokens
     */
    union {
        /** @brief Pointer to an interned string for identifiers. */
        const char* identifier;
        /** @brief 64-bit signed integer for integer literals. */
        i64 integer;
        /** @brief 64-bit floating-point for float literals. */
        double floating_point;
    } value;
};

/**
 * @class Lexer
 * @brief Processes source code and converts it into a stream of tokens.
 *
 * The Lexer is responsible for the first phase of compilation, turning raw
 * source text into a sequence of tokens that the parser can understand. It
 * handles skipping whitespace, comments, and recognizing keywords, identifiers,
 * literals, and operators.
 */
class Lexer {
private:
    const char* current;      ///< Pointer to the current character in the source buffer.
    SourceManager& source;    ///< Reference to the source manager for location tracking.
    u32 file_id;              ///< The ID of the file currently being lexed.

public:
    /**
     * @brief Constructs a new Lexer instance.
     * @param src A reference to the SourceManager containing the source files.
     * @param file_id The identifier of the specific file to be lexed from the SourceManager.
     */
    Lexer(SourceManager& src, u32 file_id);

    /**
     * @brief Scans the source code and returns the next token.
     * @return The next token found in the source stream. When the end of the
     *         file is reached, it will consistently return a token of type
     *         TOKEN_EOF.
     */
    Token nextToken();
};


#endif // LEXER_HPP
