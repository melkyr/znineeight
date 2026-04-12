#include "test_declarations.hpp"
#include "test_runner_main.hpp"

TEST_FUNC(TaggedUnion_ArrayDecomposition);
TEST_FUNC(TaggedUnion_NestedIfExpr);
TEST_FUNC(TaggedUnion_NestedSwitchExpr);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_TaggedUnion_ArrayDecomposition,
        test_TaggedUnion_NestedIfExpr,
        test_TaggedUnion_NestedSwitchExpr
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
