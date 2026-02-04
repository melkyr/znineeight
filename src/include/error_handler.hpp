#ifndef ERROR_HANDLER_HPP
#define ERROR_HANDLER_HPP

#include "source_manager.hpp"
#include "memory.hpp"

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
    ERR_NON_C89_FEATURE = 1001,

    // Type Errors (2000-2999)
    ERR_TYPE_MISMATCH = 2000,
    ERR_INVALID_RETURN_VALUE_IN_VOID_FUNCTION = 2001,
    ERR_MISSING_RETURN_VALUE = 2002,
    ERR_LIFETIME_VIOLATION = 2003,
    ERR_NULL_POINTER_DEREFERENCE = 2004,
    ERR_DOUBLE_FREE = 2005,
    ERR_BANNED_ALLOCATION_FUNCTION = 2006,

    // Semantic Errors (3000-3999)
    ERR_UNDEFINED_VARIABLE = 3000,
    ERR_UNDECLARED_TYPE = 3001,
    ERR_REDEFINITION = 3002,
    ERR_VARIABLE_CANNOT_BE_VOID = 3003,
    ERR_LVALUE_EXPECTED = 3004,
    ERR_UNDEFINED_ENUM_MEMBER = 3005,

    // Operational Errors (4000-4999)
    ERR_INVALID_OPERATION = 4000,
    ERR_INVALID_VOID_POINTER_ARITHMETIC = 4001,
    ERR_DIVISION_BY_ZERO = 4002,

    // System Errors (5000-5999)
    ERR_OUT_OF_MEMORY = 5000
};

/**
 * @enum WarningCode
 * @brief Defines numeric codes for compiler warnings.
 */
enum WarningCode {
    WARN_NULL_DEREFERENCE = 6000,
    WARN_UNINITIALIZED_POINTER = 6001,
    WARN_POTENTIAL_NULL_DEREFERENCE = 6002,
    WARN_MEMORY_LEAK = 6005,
    WARN_FREE_UNALLOCATED = 6006,
    WARN_TRANSFERRED_MEMORY = 6007,
    WARN_ARRAY_PARAMETER = 6008,

    // Extraction Analysis Warnings (7000s)
    WARN_EXTRACTION_LARGE_PAYLOAD = 7001,
    WARN_EXTRACTION_DEEP_NESTING = 7002
};

/**
 * @enum InfoCode
 * @brief Defines numeric codes for informational messages.
 */
enum InfoCode {
    // Extraction Analysis Info (8000s)
    INFO_EXTRACTION_REPORT_HEADER = 8001,
    INFO_EXTRACTION_STACK_USAGE = 8002,

    // Error Handling Validation Info (9000s)
    INFO_ERROR_HANDLING_VALIDATION = 9001
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

struct WarningReport {
    WarningCode code;
    SourceLocation location;
    const char* message;
};

/**
 * @struct InfoReport
 * @brief Represents an informational diagnostic.
 */
struct InfoReport {
    InfoCode code;
    SourceLocation location;
    const char* message;
};

/**
 * @class ErrorHandler
 * @brief Manages the reporting of compilation errors.
 *
 * This class is responsible for formatting and displaying diagnostic
 * messages to the user in a clear and consistent format. It uses
 * a SourceManager to retrieve source code context for error locations.
 */
class ErrorHandler {
private:
    SourceManager& source_manager;
    ArenaAllocator& arena_;
    DynamicArray<ErrorReport> errors_;
    DynamicArray<WarningReport> warnings_;

public:
    /**
     * @brief Constructs an ErrorHandler.
     * @param sm A reference to the SourceManager containing the source files.
     * @param arena The arena allocator to use for the error list.
     */
    ErrorHandler(SourceManager& sm, ArenaAllocator& arena)
        : source_manager(sm), arena_(arena), errors_(arena), warnings_(arena), infos_(arena) {}

    /**
     * @brief Reports a new error.
     */
    void report(ErrorCode code, SourceLocation location, const char* message, const char* hint = NULL);

    /**
     * @brief Reports a new error with a message that will be copied into the arena.
     */
    void report(ErrorCode code, SourceLocation location, const char* message, ArenaAllocator& arena, const char* hint = NULL);

    /**
     * @brief Checks if any errors have been reported.
     */
    bool hasErrors() const {
        return errors_.length() > 0;
    }

    const DynamicArray<ErrorReport>& getErrors() const {
        return errors_;
    }

    /**
     * @brief Clears all reported errors.
     */
    void reset() {
        errors_.clear();
    }

    /**
     * @brief Prints all reported errors to standard error.
     */
    void printErrors();

    /**
     * @brief Reports a new warning.
     */
    void reportWarning(WarningCode code, SourceLocation location, const char* message);

    /**
     * @brief Reports a new warning with a message that will be copied into the arena.
     */
    void reportWarning(WarningCode code, SourceLocation location, const char* message, ArenaAllocator& arena);

    /**
     * @brief Checks if any warnings have been reported.
     */
    bool hasWarnings() const {
        return warnings_.length() > 0;
    }

    /**
     * @brief Gets the list of reported warnings.
     */
    const DynamicArray<WarningReport>& getWarnings() const {
        return warnings_;
    }

    /**
     * @brief Prints all reported warnings to standard error.
     */
    void printWarnings();

    /**
     * @brief Reports a new informational message.
     */
    void reportInfo(InfoCode code, SourceLocation location, const char* message);

    /**
     * @brief Reports a new informational message with a message that will be copied into the arena.
     */
    void reportInfo(InfoCode code, SourceLocation location, const char* message, ArenaAllocator& arena);

    /**
     * @brief Checks if any informational messages have been reported.
     */
    bool hasInfos() const {
        return infos_.length() > 0;
    }

    /**
     * @brief Gets the list of reported informational messages.
     */
    const DynamicArray<InfoReport>& getInfos() const {
        return infos_;
    }

    /**
     * @brief Prints all reported informational messages to standard error.
     */
    void printInfos();

private:
    DynamicArray<InfoReport> infos_;
};

#endif // ERROR_HANDLER_HPP
