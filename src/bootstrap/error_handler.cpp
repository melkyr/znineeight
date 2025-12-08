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

    std::cerr << file->filename << "(" << report.location.line << ":" << report.location.column << "): error "
              << report.code << ": " << report.message << std::endl;

    const char* line_start = file->content;
    for (u32 i = 1; i < report.location.line; ++i) {
        const char* next_line = strchr(line_start, '\n');
        if (next_line) {
            line_start = next_line + 1;
        } else {
            line_start = file->content + file->size;
            break;
        }
    }

    const char* line_end = strchr(line_start, '\n');
    if (!line_end) {
        line_end = file->content + file->size;
    }

    std::cerr << "    " << std::string(line_start, line_end - line_start) << std::endl;

    std::cerr << "    " << std::string(report.location.column - 1, ' ') << "^" << std::endl;

    if (report.hint) {
        std::cerr << "    Hint: " << report.hint << std::endl;
    }
}
