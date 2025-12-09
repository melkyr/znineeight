#include "error_handler.hpp"
#include <iostream>
#include <string>
#include <cstring>

void ErrorHandler::printErrorReport(const ErrorReport& report) {
    const SourceFile* file = source_manager.getFile(report.location.file_id);
    if (!file) {
        std::cerr << "Error: Invalid file ID in error report." << std::endl;
        return;
    }

    // Print the main error line, e.g., "test.zig(5:10): error 1000: Unexpected token"
    std::cerr << file->filename << "(" << report.location.line << ":" << report.location.column << "): error "
              << report.code << ": " << report.message << std::endl;

    // Find the start of the line where the error occurred.
    const char* line_start = file->content;
    for (u32 i = 1; i < report.location.line; ++i) {
        const char* next_line = strchr(line_start, '\n');
        if (next_line) {
            line_start = next_line + 1;
        } else {
            // Should not happen if location is valid, but as a fallback,
            // point to the end of the file.
            line_start = file->content + file->size;
            break;
        }
    }

    // Find the end of the error line.
    const char* line_end = strchr(line_start, '\n');
    if (!line_end) {
        line_end = file->content + file->size;
    }

    // Print the source line containing the error.
    std::cerr << "    " << std::string(line_start, line_end - line_start) << std::endl;

    // Print the caret (^) under the error location.
    std::cerr << "    " << std::string(report.location.column - 1, ' ') << "^" << std::endl;

    // If a hint is provided, print it.
    if (report.hint) {
        std::cerr << "    Hint: " << report.hint << std::endl;
    }
}
