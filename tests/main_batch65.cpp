#include "test_declarations.hpp"
#include "test_runner_main.hpp"

TEST_FUNC(WhileContinue_Braceless);
TEST_FUNC(WhileContinue_Labeled);
TEST_FUNC(ForLoop_Continue);
TEST_FUNC(Loop_Defer_Continue);
TEST_FUNC(Nested_Loop_Labeled_Continue);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_WhileContinue_Braceless,
        test_WhileContinue_Labeled,
        test_ForLoop_Continue,
        test_Loop_Defer_Continue,
        test_Nested_Loop_Labeled_Continue
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
