#include "error_handler.hpp"
#include "source_manager.hpp"
#include <cstdio> // For fprintf, stderr

void ErrorHandler::report(ErrorCode code, SourceLocation location, const char* message, const char* hint) {
    ErrorReport new_report;
    new_report.code = code;
    new_report.location = location;
    new_report.message = message;
    new_report.hint = hint;
    errors_.append(new_report);
}

void ErrorHandler::printErrors() {
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
}
