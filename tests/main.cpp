#include "../src/include/test_framework.hpp"
#include <cstdio>

// Forward declarations for the single test
TEST_FUNC(Parser_Bugfix_HandlesExpressionStatement);

int main(int argc, char* argv[]) {
    // Only run the one test we're interested in.
    bool (*tests[])() = {
        test_Parser_Bugfix_HandlesExpressionStatement,
    };

    int passed = 0;
    int num_tests = sizeof(tests) / sizeof(tests[0]);

    for (int i = 0; i < num_tests; ++i) {
        if (tests[i]()) {
            passed++;
        }
    }

    printf("Passed %d/%d tests\n", passed, num_tests);
    return passed == num_tests ? 0 : 1;
}
