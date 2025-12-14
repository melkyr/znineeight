#ifndef PARSER_HPP
#define PARSER_HPP

#include "lexer.hpp"
#include "memory.hpp"
#include "error.hpp"
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

    /**
     * @brief Checks if the current token matches the given type. If it does,
     * the token is consumed and the method returns true. Otherwise, the
     * stream is not advanced and the method returns false.
     * @param type The TokenType to match against.
     * @return True if the token matches and was consumed, false otherwise.
     */
    bool match(TokenType type);

    /**
     * @brief Expects the current token to be of a specific type. If it matches,
     * the token is consumed and returned. If it does not match, an error is
     * recorded, the stream is not advanced, and the mismatched token is returned.
     * @param expected_type The expected TokenType.
     * @return The consumed token on success, or the mismatched token on failure.
     */
    Token expect(TokenType expected_type);

    /**
     * @brief Retrieves the list of errors encountered during parsing.
     * @return A pointer to the dynamic array of ErrorReport objects.
     */
    const DynamicArray<ErrorReport>* getErrors() const;

private:
    void reportError(const Token& token, const char* message);

    Token* tokens_;
    size_t token_count_;
    size_t current_index_;
    ArenaAllocator* arena_;
    DynamicArray<ErrorReport> errors_;
};

#endif // PARSER_HPP
