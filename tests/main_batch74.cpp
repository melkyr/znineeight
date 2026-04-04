#include "test_runner_main.hpp"

TEST_FUNC(AnonInit_TaggedUnion_NestedStruct);
TEST_FUNC(AnonInit_DeeplyNested);
TEST_FUNC(AnonInit_Alias);
TEST_FUNC(AnonInit_NakedTag_Coercion);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_AnonInit_TaggedUnion_NestedStruct,
        test_AnonInit_DeeplyNested,
        test_AnonInit_Alias,
        test_AnonInit_NakedTag_Coercion
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
