#include "test_runner_main.hpp"
#include "test_framework.hpp"

TEST_FUNC(MainFunction_ReturnInt_VoidReturn);
TEST_FUNC(MainFunction_ReturnInt_ErrorUnionReturn);
TEST_FUNC(MainFunction_ImplicitReturn);
TEST_FUNC(MainFunction_WithExpression);
TEST_FUNC(RecursiveTaggedUnionSize);
TEST_FUNC(JsonValueRecursiveSize);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_RecursiveTaggedUnionSize,
        test_JsonValueRecursiveSize,
        test_MainFunction_ReturnInt_VoidReturn,
        test_MainFunction_ReturnInt_ErrorUnionReturn,
        test_MainFunction_ImplicitReturn,
        test_MainFunction_WithExpression
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
