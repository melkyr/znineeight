#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
TEST_FUNC(BracelessControlFlow_If);
TEST_FUNC(BracelessControlFlow_ElseIf);
TEST_FUNC(BracelessControlFlow_While);
TEST_FUNC(BracelessControlFlow_For);
TEST_FUNC(BracelessControlFlow_ErrDefer);
TEST_FUNC(BracelessControlFlow_Defer);
TEST_FUNC(BracelessControlFlow_Nested);
TEST_FUNC(BracelessControlFlow_MixedBraced);
TEST_FUNC(BracelessControlFlow_EmptyWhile);
TEST_FUNC(BracelessControlFlow_ForBreak);
TEST_FUNC(BracelessControlFlow_CombinedDefers);
TEST_FUNC(BracelessControlFlow_InsideLifted);
TEST_FUNC(BracelessControlFlow_EmptyFor);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_BracelessControlFlow_If,
        test_BracelessControlFlow_ElseIf,
        test_BracelessControlFlow_While,
        test_BracelessControlFlow_For,
        test_BracelessControlFlow_ErrDefer,
        test_BracelessControlFlow_Defer,
        test_BracelessControlFlow_Nested,
        test_BracelessControlFlow_MixedBraced,
        test_BracelessControlFlow_EmptyWhile,
        test_BracelessControlFlow_ForBreak,
        test_BracelessControlFlow_CombinedDefers,
        test_BracelessControlFlow_InsideLifted,
        test_BracelessControlFlow_EmptyFor
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
