#include "../src/include/test_framework.hpp"

// Forward declarations for all test functions
TEST_FUNC(basic_allocation);
TEST_FUNC(multiple_allocations);
TEST_FUNC(allocation_failure);
TEST_FUNC(reset);
TEST_FUNC(aligned_allocation);
TEST_FUNC(string_interning);
TEST_FUNC(dynamic_array_append);
TEST_FUNC(dynamic_array_growth);

int main() {
    bool (*tests[])() = {
        test_basic_allocation,
        test_multiple_allocations,
        test_allocation_failure,
        test_reset,
        test_aligned_allocation,
        test_string_interning,
        test_dynamic_array_append,
        test_dynamic_array_growth,
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
