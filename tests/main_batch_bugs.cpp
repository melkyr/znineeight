#include "test_runner_main.hpp"
#include "test_framework.hpp"

TEST_FUNC(SwitchLifter_NestedControlFlow);
TEST_FUNC(Codegen_StringSplit);
TEST_FUNC(Codegen_ForPtrToArray);
TEST_FUNC(ArrayProperty_Len);
TEST_FUNC(ArrayProperty_ComptimeLen);
TEST_FUNC(MainFunction_ReturnInt_Validation);
TEST_FUNC(MainFunction_ErrorUnion_Validation);
TEST_FUNC(RecursiveTaggedUnion_LayoutValidation);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_SwitchLifter_NestedControlFlow,
        test_Codegen_StringSplit,
        test_Codegen_ForPtrToArray,
        test_ArrayProperty_Len,
        test_ArrayProperty_ComptimeLen,
        test_MainFunction_ReturnInt_Validation,
        test_MainFunction_ErrorUnion_Validation,
        test_RecursiveTaggedUnion_LayoutValidation
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
