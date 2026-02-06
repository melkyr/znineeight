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

    report(code, location, msg_copy, hint);
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
