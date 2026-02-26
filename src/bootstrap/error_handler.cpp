#include "error_handler.hpp"
#include "source_manager.hpp"
#include "platform.hpp"

// --- Safe String Building Helpers ---

// Appends a null-terminated C-string to the buffer.
static void append_string(DynamicArray<char>& buffer, const char* str) {
    if (!str) return;
    size_t len = plat_strlen(str);
    for (size_t i = 0; i < len; ++i) {
        buffer.append(str[i]);
    }
}

// Appends a substring to the buffer.
static void append_substring(DynamicArray<char>& buffer, const char* start, const char* end) {
    if (!start || !end || start >= end) return;
    for (const char* p = start; p < end; ++p) {
        buffer.append(*p);
    }
}

// Appends a sequence of characters to the buffer.
static void append_chars(DynamicArray<char>& buffer, char c, size_t count) {
    for (size_t i = 0; i < count; ++i) {
        buffer.append(c);
    }
}

// Converts a u32 to a string and appends it to the buffer.
static void append_u32(DynamicArray<char>& buffer, u32 value) {
    if (value == 0) {
        buffer.append('0');
        return;
    }

    char num_buffer[11]; // Max 10 digits for u32 + null terminator
    char* p = &num_buffer[10];
    *p = '\0';

    u32 temp = value;
    do {
        *--p = '0' + (temp % 10);
        temp /= 10;
    } while (temp > 0);

    append_string(buffer, p);
}

void ErrorHandler::report(ErrorCode code, SourceLocation location, const char* message, const char* hint) {
    ErrorReport new_report;
    new_report.code = code;
    new_report.location = location;
    new_report.message = message;
    new_report.hint = hint;
    errors_.append(new_report);
}

bool ErrorHandler::hasErrorCode(ErrorCode code) const {
    for (size_t i = 0; i < errors_.length(); ++i) {
        if (errors_[i].code == code) {
            return true;
        }
    }
    return false;
}

const char* ErrorHandler::getMessage(ErrorCode code) {
    switch (code) {
        /* Syntax Errors */
        case ERR_SYNTAX_ERROR:                  return "syntax error";
        case ERR_NON_C89_FEATURE:               return "non-C89 feature";
        case ERR_UNSUPPORTED_FEATURE:           return "unsupported language feature";

        /* Type Errors */
        case ERR_TYPE_MISMATCH:                 return "type mismatch";
        case ERR_INVALID_RETURN_VALUE_IN_VOID_FUNCTION: return "void function should not return a value";
        case ERR_MISSING_RETURN_VALUE:          return "missing return value";
        case ERR_LIFETIME_VIOLATION:            return "lifetime violation";
        case ERR_NULL_POINTER_DEREFERENCE:      return "null pointer dereference";
        case ERR_DOUBLE_FREE:                   return "double free";
        case ERR_BANNED_ALLOCATION_FUNCTION:    return "call to forbidden allocation function";
        case ERR_CAST_TARGET_NOT_POINTER:       return "target type of @ptrCast must be a pointer";
        case ERR_CAST_SOURCE_NOT_POINTER:       return "source of @ptrCast must be a pointer";
        case ERR_SIZE_OF_INCOMPLETE_TYPE:       return "@sizeOf applied to incomplete type";
        case ERR_INT_CAST_OVERFLOW:             return "integer cast overflow";
        case ERR_FLOAT_CAST_OVERFLOW:           return "float cast overflow";
        case ERR_CAST_SOURCE_NOT_INTEGER:       return "source of @intCast must be an integer";
        case ERR_CAST_SOURCE_NOT_FLOAT:         return "source of @floatCast must be a float";
        case ERR_CAST_TARGET_NOT_INTEGER:       return "target of @intCast must be an integer";
        case ERR_CAST_TARGET_NOT_FLOAT:         return "target of @floatCast must be a float";
        case ERR_OFFSETOF_NON_AGGREGATE:        return "@offsetOf called on non-aggregate type";
        case ERR_OFFSETOF_FIELD_NOT_FOUND:      return "field not found in @offsetOf";
        case ERR_OFFSETOF_INCOMPLETE_TYPE:      return "@offsetOf cannot be used on incomplete type";
        case ERR_GLOBAL_VAR_NON_CONSTANT_INIT:  return "global variable must have constant initializer";
        case ERR_FUNCTION_CANNOT_RETURN_ARRAY:  return "functions cannot return arrays in C89";
        case ERR_TRY_ON_NON_ERROR_UNION:        return "try operand must be an error union";
        case ERR_TRY_IN_NON_ERROR_FUNCTION:     return "try can only be used in error-returning functions";
        case ERR_CATCH_ON_NON_ERROR_UNION:      return "catch operand must be an error union";
        case ERR_CATCH_TYPE_MISMATCH:           return "catch fallback type mismatch";
        case ERR_TRY_INCOMPATIBLE_ERROR_SETS:   return "incompatible error sets in try";

        /* Semantic Errors */
        case ERR_UNDEFINED_VARIABLE:            return "use of undeclared identifier";
        case ERR_UNDECLARED_TYPE:               return "use of undeclared type";
        case ERR_REDEFINITION:                  return "redefinition";
        case ERR_VARIABLE_CANNOT_BE_VOID:       return "variables cannot be declared as 'void'";
        case ERR_LVALUE_EXPECTED:               return "l-value expected";
        case ERR_UNDEFINED_ENUM_MEMBER:         return "enum has no such member";
        case ERR_EXTERN_FN_WITH_BODY:           return "extern function cannot have a body";
        case ERR_BREAK_OUTSIDE_LOOP:            return "break outside of loop";
        case ERR_CONTINUE_OUTSIDE_LOOP:         return "continue outside of loop";
        case ERR_UNKNOWN_LABEL:                 return "unknown loop label";
        case ERR_DUPLICATE_LABEL:               return "duplicate loop label";
        case ERR_RETURN_INSIDE_DEFER:           return "return inside defer";
        case ERR_BREAK_INSIDE_DEFER:            return "break inside defer";
        case ERR_CONTINUE_INSIDE_DEFER:         return "continue inside defer";

        /* Operational Errors */
        case ERR_INVALID_OPERATION:             return "invalid operation";
        case ERR_INVALID_VOID_POINTER_ARITHMETIC: return "pointer arithmetic on 'void*' is not allowed";
        case ERR_DIVISION_BY_ZERO:              return "division by zero";
        case ERR_POINTER_ARITHMETIC_INVALID_OPERATOR: return "invalid operator for pointer arithmetic";
        case ERR_POINTER_ARITHMETIC_NON_UNSIGNED: return "pointer arithmetic requires an unsigned offset";
        case ERR_POINTER_ARITHMETIC_VOID:       return "arithmetic on void or incomplete pointer is not allowed";
        case ERR_POINTER_SUBTRACTION_INCOMPATIBLE: return "cannot subtract pointers to different types";
        case ERR_INVALID_OP_FUNCTION_POINTER:   return "invalid operation on function pointer";
        case ERR_DEREF_FUNCTION_POINTER:        return "cannot dereference a function pointer";
        case ERR_INDEX_FUNCTION_POINTER:        return "cannot index into a function pointer";

        /* System Errors */
        case ERR_OUT_OF_MEMORY:                 return "out of memory";
        case ERR_INTERNAL_ERROR:                return "internal compiler error";
        case ERR_FILE_NOT_FOUND:                return "file not found";

        default:                                return "unknown error";
    }
}

void ErrorHandler::reportWarning(WarningCode code, SourceLocation location, const char* message) {
    WarningReport new_warning;
    new_warning.code = code;
    new_warning.location = location;
    new_warning.message = message;
    warnings_.append(new_warning);
}

void ErrorHandler::reportWarning(WarningCode code, SourceLocation location, const char* message, ArenaAllocator& arena) {
    size_t msg_len = plat_strlen(message);
    char* msg_copy = (char*)arena.alloc(msg_len + 1);
    plat_memcpy(msg_copy, message, msg_len + 1);

    reportWarning(code, location, msg_copy);
}

void ErrorHandler::report(ErrorCode code, SourceLocation location, const char* message, ArenaAllocator& arena, const char* hint) {
    size_t msg_len = plat_strlen(message);
    char* msg_copy = (char*)arena.alloc(msg_len + 1);
    plat_memcpy(msg_copy, message, msg_len + 1);

    char* hint_copy = NULL;
    if (hint) {
        size_t hint_len = plat_strlen(hint);
        hint_copy = (char*)arena.alloc(hint_len + 1);
        plat_memcpy(hint_copy, hint, hint_len + 1);
    }

    report(code, location, msg_copy, hint_copy);
}

void ErrorHandler::printErrors() {
    DynamicArray<char> buffer(arena_);
    for (size_t i = 0; i < errors_.length(); ++i) {
        const ErrorReport& report = errors_[i];
        const SourceFile* file = source_manager.getFile(report.location.file_id);

        // Format: filename:line:column: error: message
        buffer.clear();
        if (file) {
            append_string(buffer, file->filename);
            append_string(buffer, ":");
            append_u32(buffer, report.location.line);
            append_string(buffer, ":");
            append_u32(buffer, report.location.column);
            append_string(buffer, ": ");
        }
        append_string(buffer, "error: ");
        append_string(buffer, report.message);
        append_string(buffer, "\n");
        buffer.append('\0'); // Null-terminate
        plat_print_error(buffer.getData());
        plat_print_debug(buffer.getData());

        if (file) {
            // Find and print the line of code
            const char* line_start = file->content;
            for (u32 line = 1; line < report.location.line; ++line) {
                while (*line_start != '\n' && *line_start != '\0') {
                    line_start++;
                }
                if (*line_start == '\n') {
                    line_start++;
                }
            }

            const char* line_end = line_start;
            while (*line_end != '\n' && *line_end != '\0') {
                line_end++;
            }

            // Print the line
            buffer.clear();
            append_string(buffer, "    ");
            append_substring(buffer, line_start, line_end);
            append_string(buffer, "\n");
            buffer.append('\0');
            plat_print_error(buffer.getData());
            plat_print_debug(buffer.getData());

            // Print the caret
            buffer.clear();
            append_string(buffer, "    ");
            append_chars(buffer, ' ', report.location.column > 0 ? report.location.column - 1 : 0);
            append_string(buffer, "^\n");
            buffer.append('\0');
            plat_print_error(buffer.getData());
            plat_print_debug(buffer.getData());
        }

        if (report.hint) {
            buffer.clear();
            append_string(buffer, "    hint: ");
            append_string(buffer, report.hint);
            append_string(buffer, "\n");
            buffer.append('\0');
            plat_print_error(buffer.getData());
            plat_print_debug(buffer.getData());
        }
    }
}

void ErrorHandler::reportInfo(InfoCode code, SourceLocation location, const char* message) {
    InfoReport new_info;
    new_info.code = code;
    new_info.location = location;
    new_info.message = message;
    infos_.append(new_info);
}

void ErrorHandler::reportInfo(InfoCode code, SourceLocation location, const char* message, ArenaAllocator& arena) {
    size_t msg_len = plat_strlen(message);
    char* msg_copy = (char*)arena.alloc(msg_len + 1);
    plat_memcpy(msg_copy, message, msg_len + 1);

    reportInfo(code, location, msg_copy);
}

void ErrorHandler::printInfos() {
    DynamicArray<char> buffer(arena_);
    for (size_t i = 0; i < infos_.length(); ++i) {
        const InfoReport& report = infos_[i];

        buffer.clear();
        if (report.location.file_id != 0) {
            const SourceFile* file = source_manager.getFile(report.location.file_id);
            if (file) {
                append_string(buffer, file->filename);
                append_string(buffer, ":");
                append_u32(buffer, report.location.line);
                append_string(buffer, ":");
                append_u32(buffer, report.location.column);
                append_string(buffer, ": ");
            }
        }
        append_string(buffer, "info: ");
        append_string(buffer, report.message);
        append_string(buffer, "\n");
        buffer.append('\0');
        plat_print_info(buffer.getData());
        plat_print_debug(buffer.getData());
    }
}

void ErrorHandler::printWarnings() {
    DynamicArray<char> buffer(arena_);
    for (size_t i = 0; i < warnings_.length(); ++i) {
        const WarningReport& report = warnings_[i];
        const SourceFile* file = source_manager.getFile(report.location.file_id);

        buffer.clear();
        if (file) {
            append_string(buffer, file->filename);
            append_string(buffer, ":");
            append_u32(buffer, report.location.line);
            append_string(buffer, ":");
            append_u32(buffer, report.location.column);
            append_string(buffer, ": ");
        }
        append_string(buffer, "warning: ");
        append_string(buffer, report.message);
        append_string(buffer, "\n");
        buffer.append('\0');
        plat_print_error(buffer.getData()); // Warnings go to stderr
        plat_print_debug(buffer.getData());

        if (file) {
            // Find and print the line of code
            const char* line_start = file->content;
            for (u32 line = 1; line < report.location.line; ++line) {
                while (*line_start != '\n' && *line_start != '\0') {
                    line_start++;
                }
                if (*line_start == '\n') {
                    line_start++;
                }
            }

            const char* line_end = line_start;
            while (*line_end != '\n' && *line_end != '\0') {
                line_end++;
            }

            // Print the line
            buffer.clear();
            append_string(buffer, "    ");
            append_substring(buffer, line_start, line_end);
            append_string(buffer, "\n");
            buffer.append('\0');
            plat_print_error(buffer.getData());
            plat_print_debug(buffer.getData());

            // Print the caret
            buffer.clear();
            append_string(buffer, "    ");
            append_chars(buffer, ' ', report.location.column > 0 ? report.location.column - 1 : 0);
            append_string(buffer, "^\n");
            buffer.append('\0');
            plat_print_error(buffer.getData());
            plat_print_debug(buffer.getData());
        }
    }
}
