#ifndef PARSER_HPP
#define PARSER_HPP

#include "lexer.hpp"
#include "memory.hpp"
#include "ast.hpp"
#include <cstddef> // For size_t
#include <cassert> // For assert()

class Parser {
public:
    /**
     * @brief Constructs a new Parser instance.
     * @param tokens A pointer to the array of tokens from the lexer.
     * @param count The total number of tokens in the stream.
     * @param arena A pointer to the ArenaAllocator for memory management.
     */
    Parser(Token* tokens, size_t count, ArenaAllocator* arena);

    /**
     * @brief Parses a type expression from the token stream.
     * @return A pointer to the root ASTNode of the parsed type.
     */
    ASTNode* parseType();

    /**
     * @brief Parses a top-level variable declaration (`var` or `const`).
     * @return A pointer to the ASTNode representing the variable declaration.
     */
    ASTNode* parseVarDecl();

    /**
     * @brief Parses an expression. NOTE: For now, only supports integer literals.
     * @return A pointer to the ASTNode representing the expression.
     */
    ASTNode* parseExpression();

    /**
     * @brief Consumes the current token and advances the stream position by one.
     * @return The token that was consumed.
     */
    Token advance();

    /**
     * @brief Returns the current token without consuming it.
     * @return A constant reference to the current token.
     */
    const Token& peek() const;

    /**
     * @brief Checks if the parser has consumed all tokens, including EOF.
     * @return True if the end of the token stream has been reached, false otherwise.
     */
    bool is_at_end() const;

private:
    /**
     * @brief If the current token matches the expected type, consumes it and returns true.
     * @param type The expected token type.
     * @return True if the token matched and was consumed, false otherwise.
     */
    bool match(TokenType type);

    /**
     * @brief If the current token matches the expected type, consumes it. Otherwise, reports an error and aborts.
     * @param type The expected token type.
     * @param msg The error message to display if the token does not match.
     * @return The consumed token.
     */
    Token expect(TokenType type, const char* msg);

    /**
     * @brief Reports a syntax error and terminates the compilation.
     * @param msg The error message to display.
     */
    void error(const char* msg);

    /**
     * @brief Checks if a token represents a primitive type keyword.
     * @param token The token to check.
     * @return True if the token is a primitive type, false otherwise.
     */
    bool isPrimitiveType(const Token& token);

    /** @brief Parses a primitive type (e.g., `i32`, `bool`). */
    ASTNode* parsePrimitiveType();

    /** @brief Parses a pointer type (e.g., `*u8`, `**i32`). */
    ASTNode* parsePointerType();

    /** @brief Parses an array or slice type (e.g., `[]bool`, `[8]u8`). */
    ASTNode* parseArrayType();

    Token* tokens_;
    size_t token_count_;
    size_t current_index_;
    ArenaAllocator* arena_;
};

#endif // PARSER_HPP
