#ifndef ERROR_HPP
#define ERROR_HPP

#include "lexer.hpp"

/**
 * @struct ErrorReport
 * @brief Represents a single syntax error found during parsing.
 *
 * This struct is designed to be memory-safe. The error message is not a
 * dynamically allocated string in the traditional sense but is instead
 * allocated from the Parser's ArenaAllocator. This ensures that all error
 * messages are cleaned up automatically when the arena is reset.
 */
struct ErrorReport {
    /**
     * @brief The token that caused or was nearest to the error.
     * Provides location information (line, column) for the error message.
     */
    Token token;

    /**
     * @brief A pointer to the null-terminated error message.
     * This memory is managed by the ArenaAllocator.
     */
    const char* message;
};

#endif // ERROR_HPP
