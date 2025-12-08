#ifndef ERROR_HANDLER_HPP
#define ERROR_HANDLER_HPP

#include "source_manager.hpp"

// Forward declaration for the main error handling class
class ErrorHandler;

/**
 * @enum ErrorCode
 * @brief Defines numeric codes for different compiler errors.
 *
 * Each error code has a unique number to identify it programmatically.
 * The ranges are organized by compiler stage:
 * 1000s: Syntax Errors
 * 2000s: Type System Errors
 * 3000s: Symbol/Semantic Errors
 * 4000s: Operational Errors
 * 5000s: System/Environment Errors
 */
enum ErrorCode {
    // Syntax Errors (1000-1999)
    ERR_SYNTAX_ERROR = 1000,

    // Type Errors (2000-2999)
    ERR_TYPE_MISMATCH = 2000,

    // Semantic Errors (3000-3999)
    ERR_UNDEFINED_VARIABLE = 3000,

    // Operational Errors (4000-4999)
    ERR_INVALID_OPERATION = 4000,

    // System Errors (5000-5999)
    ERR_OUT_OF_MEMORY = 5000
};

/**
 * @struct ErrorReport
 * @brief Represents a single diagnosed error in the source code.
 *
 * This structure contains all the information needed to report a detailed
 * error to the user, including its location, a descriptive message,
 * and an optional hint for fixing it.
 */
struct ErrorReport {
    /// @brief The specific error code from the ErrorCode enum.
    ErrorCode code;

    /// @brief The location in the source file where the error occurred.
    SourceLocation location;

    /// @brief A descriptive message explaining the error.
    const char* message;

    /// @brief An optional hint on how to resolve the error.
    const char* hint;
};

#endif // ERROR_HANDLER_HPP
