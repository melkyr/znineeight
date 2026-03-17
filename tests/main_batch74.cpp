#include "test_runner_main.hpp"

TEST_FUNC(WhileSwitch_BreakExitsLoop);
TEST_FUNC(WhileSwitch_ContinueTargetsLoop);
TEST_FUNC(WhileSwitch_NestedLoops);
TEST_FUNC(ForSwitch_BreakExitsLoop);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_WhileSwitch_BreakExitsLoop,
        test_WhileSwitch_ContinueTargetsLoop,
        test_WhileSwitch_NestedLoops,
        test_ForSwitch_BreakExitsLoop
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
