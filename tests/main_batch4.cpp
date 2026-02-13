#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        // Memory Stability
        test_MemoryStability_TokenSupplierDanglingPointer,

        // C89 Rejection
        test_C89Rejection_Slice,
        test_C89Rejection_TryExpression,
        test_C89Rejection_CatchExpression,
        test_C89Rejection_OrelseExpression,
        test_TypeChecker_RejectSliceExpression,

        // Bug Fix Verification
        test_dynamic_array_destructor_fix,

        // Task 119
        test_Task119_DetectMalloc,
        test_Task119_DetectCalloc,
        test_Task119_DetectRealloc,
        test_Task119_DetectFree,
        test_Task119_DetectAlignedAlloc,
        test_Task119_DetectStrdup,
        test_Task119_DetectMemcpy,
        test_Task119_DetectMemset,
        test_Task119_DetectStrcpy,

        // Symbol Flags
        test_SymbolFlags_GlobalVariable,
        test_SymbolFlags_SymbolBuilder,

        // Utils Bug Fix
        test_safe_append_null_termination,
        test_safe_append_explicit_check,
        test_simple_itoa_null_termination,

        // Lifetime Analysis
        test_Lifetime_DirectReturnLocalAddress,
        test_Lifetime_ReturnLocalPointer,
        test_Lifetime_ReturnParamOK,
        test_Lifetime_ReturnAddrOfParam,
        test_Lifetime_ReturnGlobalOK,
        test_Lifetime_ReassignedPointerOK,

        // Null Pointer Analysis
        test_NullPointerAnalyzer_BasicTracking,
        test_NullPointerAnalyzer_PersistentStateTracking,
        test_NullPointerAnalyzer_AssignmentTracking,
        test_NullPointerAnalyzer_IfNullGuard,
        test_NullPointerAnalyzer_IfElseMerge,
        test_NullPointerAnalyzer_WhileGuard,
        test_NullPointerAnalyzer_WhileConservativeReset,
        test_NullPointerAnalyzer_Shadowing,
        test_NullPointerAnalyzer_NoLeakage,

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
        test_DoubleFree_NestedDeferScopes,
        test_DoubleFree_PointerAliasing,
        test_DoubleFree_DeferInLoop,
        test_DoubleFree_ConditionalAllocUnconditionalFree,

        // Integration Tests
        test_Integration_FullPipeline,
        test_Integration_CorrectUsage
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
