#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ASTLifter_BasicIf,
        test_ASTLifter_Nested
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
