#ifndef LEXER_HPP
#define LEXER_HPP

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

#endif // LEXER_HPP
