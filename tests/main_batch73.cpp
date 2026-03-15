#include "test_runner_main.hpp"

TEST_FUNC(Phase7_ValidMutualRecursionPointers);
TEST_FUNC(Phase7_InvalidValueCycle);
TEST_FUNC(Phase7_DefinitionOrderValueDependency);
TEST_FUNC(Phase7_PointerDependencyForwardDecl);
TEST_FUNC(Phase7_TaggedUnionStructOrdering);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Phase7_ValidMutualRecursionPointers,
        test_Phase7_InvalidValueCycle,
        test_Phase7_DefinitionOrderValueDependency,
        test_Phase7_PointerDependencyForwardDecl,
        test_Phase7_TaggedUnionStructOrdering
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
