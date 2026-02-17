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
    ArenaAllocator arena(1024 * 1024);
    SourceManager sm(arena);
    ErrorHandler eh(sm, arena);

    const char* test_filename = "test.zig";
    const char* test_content = "var x: i32 = \"hello\";\n";
    u32 file_id = sm.addFile(test_filename, test_content, strlen(test_content));

    // 2. Redirect stderr
    std::stringstream buffer;
    std::streambuf* old_stderr = std::cerr.rdbuf(buffer.rdbuf());

    // 3. Action
    eh.report(ERR_TYPE_MISMATCH, SourceLocation{file_id, 1, 15}, "Cannot assign 'string' to 'i32'", "Use an integer literal instead.");
    eh.printErrors();

    // 4. Restore stderr and assert
    std::cerr.rdbuf(old_stderr);

    std::string expected_output =
        "test.zig(1:15): error 2000: Cannot assign 'string' to 'i32'\n"
        "    var x: i32 = \"hello\";\n"
        "                  ^\n"
        "    Hint: Use an integer literal instead.";

    std::string actual_output = buffer.str();

    // Trim trailing newlines from both strings for C++98 compatibility
    while (!actual_output.empty() && actual_output[actual_output.length() - 1] == '\n') {
        actual_output.erase(actual_output.length() - 1);
    }
    while (!expected_output.empty() && expected_output[expected_output.length() - 1] == '\n') {
        expected_output.erase(expected_output.length() - 1);
    }

    ASSERT_EQ(expected_output, actual_output);

    return true;
}

// Note: main function removed to avoid multiple definition errors.
// The primary test runner is in tests/main.cpp.
