#include "error_handler.hpp"
#include "source_manager.hpp"

#ifdef _WIN32
#include <windows.h>
#include <string.h> // For strcpy, strcat

// A simple itoa implementation to avoid sprintf
static void u32_to_string(u32 value, char* buffer) {
    char* p = buffer;
    if (value == 0) {
        *p++ = '0';
        *p = '\0';
        return;
    }

    u32 temp = value;
    int len = 0;
    while (temp > 0) {
        temp /= 10;
        len++;
    }

    p += len;
    *p-- = '\0';

    while (value > 0) {
        *p-- = '0' + (value % 10);
        value /= 10;
    }
}
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
    for (size_t i = 0; i < errors_.length(); ++i) {
        const ErrorReport& report = errors_[i];
        const SourceFile* file = source_manager.getFile(report.location.file_id);

        char buffer[512];
        char num_buffer[12];

        // Format: filename:line:column: error: message
        strcpy(buffer, file->filename);
        strcat(buffer, ":");
        u32_to_string(report.location.line, num_buffer);
        strcat(buffer, num_buffer);
        strcat(buffer, ":");
        u32_to_string(report.location.column, num_buffer);
        strcat(buffer, num_buffer);
        strcat(buffer, ": error: ");
        strcat(buffer, report.message);
        strcat(buffer, "\n");
        OutputDebugStringA(buffer);

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
        char line_buffer[512];
        strcpy(line_buffer, "    ");
        strncat(line_buffer, line_start, line_end - line_start);
        strcat(line_buffer, "\n");
        OutputDebugStringA(line_buffer);

        // Print the caret
        char caret_buffer[512];
        strcpy(caret_buffer, "    ");
        for (u32 col = 1; col < report.location.column; ++col) {
            strcat(caret_buffer, " ");
        }
        strcat(caret_buffer, "^\n");
        OutputDebugStringA(caret_buffer);

        if (report.hint) {
            strcpy(buffer, "    hint: ");
            strcat(buffer, report.hint);
            strcat(buffer, "\n");
            OutputDebugStringA(buffer);
        }
    }
#endif
}
