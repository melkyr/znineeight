#include "test_runner_main.hpp"

extern bool test_DeferIntegration_Basic();
extern bool test_DeferIntegration_LIFO();
extern bool test_DeferIntegration_Return();
extern bool test_DeferIntegration_NestedScopes();
extern bool test_DeferIntegration_Break();
extern bool test_DeferIntegration_LabeledBreak();
extern bool test_DeferIntegration_Continue();
extern bool test_DeferIntegration_NestedContinue();
extern bool test_DeferIntegration_RejectReturn();
extern bool test_DeferIntegration_RejectBreak();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_DeferIntegration_Basic,
        test_DeferIntegration_LIFO,
        test_DeferIntegration_Return,
        test_DeferIntegration_NestedScopes,
        test_DeferIntegration_Break,
        test_DeferIntegration_LabeledBreak,
        test_DeferIntegration_Continue,
        test_DeferIntegration_NestedContinue,
        test_DeferIntegration_RejectReturn,
        test_DeferIntegration_RejectBreak
    };
    return run_batch(argc, argv, tests, 10);
}
