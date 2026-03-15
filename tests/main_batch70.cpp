#include "test_runner_main.hpp"

TEST_FUNC(Unreachable_Statement);
TEST_FUNC(Unreachable_DeadCode);
TEST_FUNC(Unreachable_Initializer);
TEST_FUNC(Unreachable_ErrDefer);
TEST_FUNC(Unreachable_IfExpr);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Unreachable_Statement,
        test_Unreachable_DeadCode,
        test_Unreachable_Initializer,
        test_Unreachable_ErrDefer,
        test_Unreachable_IfExpr
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
