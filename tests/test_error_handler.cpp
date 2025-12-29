#include "error_handler.hpp"
#include "source_manager.hpp"
#include "memory.hpp"
#include <cstdio>
#include <iostream>
#include <string>
#include <sstream>
#include <cstring>

// A simple assertion macro for testing
#define ASSERT_EQ(expected, actual) \
    if ((expected) != (actual)) { \
        fprintf(stderr, "Assertion failed: expected \\n'%s'\\n, but got \\n'%s'\\n. At %s:%d\\n", \
                (expected).c_str(), (actual).c_str(), __FILE__, __LINE__); \
        return false; \
    }

bool test_print_error_report() {
    // 1. Setup
    ArenaAllocator arena(8192);
    SourceManager sm(arena);
    ErrorHandler eh(sm);

    const char* test_filename = "test.zig";
    const char* test_content = "var x: i32 = \"hello\";\n";
    u32 file_id = sm.addFile(test_filename, test_content, strlen(test_content));

    ErrorReport report;
    report.code = ERR_TYPE_MISMATCH;
    report.location.file_id = file_id;
    report.location.line = 1;
    report.location.column = 15;
    report.message = "Cannot assign 'string' to 'i32'";
    report.hint = "Use an integer literal instead.";

    // 2. Redirect stderr
    std::stringstream buffer;
    std::streambuf* old_stderr = std::cerr.rdbuf(buffer.rdbuf());

    // 3. Action
    eh.printErrorReport(report);

    // 4. Restore stderr and assert
    std::cerr.rdbuf(old_stderr);

    std::string expected_output =
        "test.zig(1:15): error 2000: Cannot assign 'string' to 'i32'\n"
        "    var x: i32 = \"hello\";\n"
        "                  ^\n"
        "    Hint: Use an integer literal instead.";

    std::string actual_output = buffer.str();

    // Trim trailing newlines from both strings
    while (!actual_output.empty() && actual_output.back() == '\n') {
        actual_output.pop_back();
    }
    while (!expected_output.empty() && expected_output.back() == '\n') {
        expected_output.pop_back();
    }


    ASSERT_EQ(expected_output, actual_output);

    return true;
}

int main() {
    if (test_print_error_report()) {
        printf("test_error_handler passed.\n");
        return 0;
    } else {
        printf("test_error_handler failed.\n");
        return 1;
    }
}
