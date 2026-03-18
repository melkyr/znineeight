#include "test_runner_main.hpp"

TEST_FUNC(Phase3_ErrorUnionRecursion);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Phase3_ErrorUnionRecursion
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
