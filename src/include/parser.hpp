#ifndef PARSER_HPP
#define PARSER_HPP

#include "lexer.hpp"
#include "memory.hpp"
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

private:
    Token* tokens_;
    size_t token_count_;
    size_t current_index_;
    ArenaAllocator* arena_;
};

#endif // PARSER_HPP
