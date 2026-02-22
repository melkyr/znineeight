#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ErrorHandling_ErrorSetDefinition,
        test_ErrorHandling_ErrorLiteral,
        test_ErrorHandling_SuccessWrapping,
        test_ErrorHandling_VoidPayload,
        test_ErrorHandling_TryExpression,
        test_ErrorHandling_CatchExpression,
        test_ErrorHandling_NestedErrorUnion,
        test_ErrorHandling_StructField,
        test_ErrorHandling_C89Execution,
        test_ErrorHandling_DuplicateTags,
        test_ErrorHandling_SetMerging,
        test_ErrorHandling_Layout
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
