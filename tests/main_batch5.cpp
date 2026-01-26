#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        // Double Free Analysis
        test_DoubleFree_SimpleDoubleFree,
        test_DoubleFree_BasicTracking,
        test_DoubleFree_UninitializedFree,
        test_DoubleFree_MemoryLeak,
        test_DoubleFree_DeferDoubleFree,
        test_DoubleFree_ReassignmentLeak,
        test_DoubleFree_NullReassignmentLeak,
        test_DoubleFree_ReturnExempt,
        test_DoubleFree_SwitchAnalysis,
        test_DoubleFree_TryAnalysis,
        test_DoubleFree_TryAnalysisComplex,
        test_DoubleFree_CatchAnalysis,
        test_DoubleFree_BinaryOpAnalysis,
        test_DoubleFree_LocationInLeakWarning,
        test_DoubleFree_LocationInReassignmentLeak,
        test_DoubleFree_LocationInDoubleFreeError,
        test_DoubleFree_TransferTracking,
        test_DoubleFree_DeferContextInError,
        test_DoubleFree_ErrdeferContextInError,
        test_DoubleFree_IfElseBranching,
        test_DoubleFree_IfElseBothFree,
        test_DoubleFree_WhileConservative,
        test_DoubleFree_SwitchPathAware,
        test_DoubleFree_SwitchBothFree,
        test_DoubleFree_TryPathAware,
        test_DoubleFree_CatchPathAware,
        test_DoubleFree_OrelsePathAware,
        test_DoubleFree_LoopConservativeVerification,
        // Integration Tests
        test_Integration_FullPipeline,
        test_Integration_CorrectUsage
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
