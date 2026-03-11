#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations of the new unit tests
bool test_clone_basic();
bool test_clone_binary_op();
bool test_traversal_binary_op();
bool test_traversal_block();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_clone_basic,
        test_clone_binary_op,
        test_traversal_binary_op,
        test_traversal_block
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
