#include "test_runner_main.hpp"
#include "integration/switch_range_tests.cpp"

bool (*tests[])() = {
    test_SwitchRange_Inclusive,
    test_SwitchRange_Exclusive,
    test_SwitchRange_ErrorNonConstant,
    test_SwitchRange_ErrorEmpty,
    test_SwitchRange_ErrorTooLarge,
    test_SwitchRange_ErrorCaptureWithRange
};

int main(int argc, char* argv[]) {
    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
