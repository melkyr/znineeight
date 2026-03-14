#include "test_declarations.hpp"
#include "test_runner_main.hpp"

TEST_FUNC(SliceDefinition_PrivateFunction);
TEST_FUNC(SliceDefinition_RecursiveType);
TEST_FUNC(SliceDefinition_NestedType);
TEST_FUNC(SliceDefinition_PublicSignatureNested);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_SliceDefinition_PrivateFunction,
        test_SliceDefinition_RecursiveType,
        test_SliceDefinition_NestedType,
        test_SliceDefinition_PublicSignatureNested
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
