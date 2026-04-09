#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_DoubleFree_StructFieldTracking,
        test_DoubleFree_StructFieldLeak,
        test_DoubleFree_ArrayCollapseTracking,
        test_DoubleFree_ErrorUnionAllocation,
        test_DoubleFree_LoopMergingPreservesUnmodified
    };
    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
