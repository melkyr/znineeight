#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include <cstdio>

// Forward declaration for the helper function that will be implemented in main.cpp
bool expect_parser_oom_abort(const char* source_code);

/**
 * @brief Tests that the parser aborts when an arena allocation fails.
 */
TEST_FUNC(Parser_AbortOnAllocationFailure) {
    // Parsing even a simple integer literal requires allocating an ASTNode.
    // With a tiny arena (which will be set up in the test harness in main.cpp),
    // this allocation should fail. The parser should detect the NULL return
    // and call its error() function, which aborts the process.
    printf("RUNNING: Parser_AbortOnAllocationFailure\n");
    bool did_abort = expect_parser_oom_abort("123");
    ASSERT_TRUE(did_abort);
    if (!did_abort) {
        printf("FAILED: Parser did not abort on allocation failure.\n");
    }
    return did_abort;
}
