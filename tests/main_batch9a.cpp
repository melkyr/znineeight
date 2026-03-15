#include "test_runner_main.hpp"

TEST_FUNC(Phase9a_ModuleQualifiedTaggedUnion);
TEST_FUNC(Phase9a_LocalAliasTaggedUnion);
TEST_FUNC(Phase9a_RecursiveAliasEnum);
TEST_FUNC(Phase9a_ErrorSetAlias);
TEST_FUNC(Phase9a_ModuleQualifiedEnum);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Phase9a_ModuleQualifiedTaggedUnion,
        test_Phase9a_LocalAliasTaggedUnion,
        test_Phase9a_RecursiveAliasEnum,
        test_Phase9a_ErrorSetAlias,
        test_Phase9a_ModuleQualifiedEnum
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
