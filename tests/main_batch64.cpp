#include "test_declarations.hpp"
#include "test_runner_main.hpp"

TEST_FUNC(WhileContinueLabel);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_WhileContinueLabel
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
