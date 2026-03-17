#include "test_runner_main.hpp"
#include "test_framework.hpp"

TEST_FUNC(SwitchLifter_NestedControlFlow);
TEST_FUNC(Codegen_StringSplit);
TEST_FUNC(Codegen_ForPtrToArray);
TEST_FUNC(ArrayProperty_Len);
TEST_FUNC(ArrayProperty_ComptimeLen);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_SwitchLifter_NestedControlFlow,
        test_Codegen_StringSplit,
        test_Codegen_ForPtrToArray,
        test_ArrayProperty_Len,
        test_ArrayProperty_ComptimeLen
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
