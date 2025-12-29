#include "error_handler.hpp"
#include "source_manager.hpp"

#ifdef _WIN32
#include <windows.h>
#include <string.h> // For strlen

// --- Safe String Building Helpers ---

// Appends a null-terminated C-string to the buffer.
static void append_string(DynamicArray<char>& buffer, const char* str) {
    if (!str) return;
    size_t len = strlen(str);
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

#else
#include <cstdio> // For fprintf, stderr
#endif

void ErrorHandler::report(ErrorCode code, SourceLocation location, const char* message, const char* hint) {
    ErrorReport new_report;
    new_report.code = code;
    new_report.location = location;
    new_report.message = message;
    new_report.hint = hint;
    errors_.append(new_report);
}

void ErrorHandler::printErrors() {
#ifdef _WIN32
    DynamicArray<char> buffer(arena_);
    for (size_t i = 0; i < errors_.length(); ++i) {
        const ErrorReport& report = errors_[i];
        const SourceFile* file = source_manager.getFile(report.location.file_id);

        // Format: filename:line:column: error: message
        buffer.clear();
        append_string(buffer, file->filename);
        append_string(buffer, ":");
        append_u32(buffer, report.location.line);
        append_string(buffer, ":");
        append_u32(buffer, report.location.column);
        append_string(buffer, ": error: ");
        append_string(buffer, report.message);
        append_string(buffer, "\n");
        buffer.append('\0'); // Null-terminate
        OutputDebugStringA(buffer.data());

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
        OutputDebugStringA(buffer.data());

        // Print the caret
        buffer.clear();
        append_string(buffer, "    ");
        append_chars(buffer, ' ', report.location.column > 0 ? report.location.column - 1 : 0);
        append_string(buffer, "^\n");
        buffer.append('\0');
        OutputDebugStringA(buffer.data());

        if (report.hint) {
            buffer.clear();
            append_string(buffer, "    hint: ");
            append_string(buffer, report.hint);
            append_string(buffer, "\n");
            buffer.append('\0');
            OutputDebugStringA(buffer.data());
        }
    }
#else
    for (size_t i = 0; i < errors_.length(); ++i) {
        const ErrorReport& report = errors_[i];
        const SourceFile* file = source_manager.getFile(report.location.file_id);

        fprintf(stderr, "%s:%u:%u: error: %s\n",
                file->filename, report.location.line, report.location.column, report.message);

        // Print the line of code
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

        fprintf(stderr, "    %.*s\n", (int)(line_end - line_start), line_start);

        // Print the caret
        fprintf(stderr, "    ");
        for (u32 col = 1; col < report.location.column; ++col) {
            fprintf(stderr, " ");
        }
        fprintf(stderr, "^\n");

        if (report.hint) {
            fprintf(stderr, "    hint: %s\n", report.hint);
        }
    }
#endif
}
