#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ArrayIntegration_FixedSizeDecl,
        test_ArrayIntegration_Indexing,
        test_ArrayIntegration_MultiDimensionalIndexing,
        test_EnumIntegration_BasicEnum,
        test_EnumIntegration_MemberAccess,
        test_EnumIntegration_RejectNonIntBacking,
        test_UnionIntegration_BareUnion,
        test_UnionIntegration_RejectTaggedUnion,
        test_SwitchIntegration_Basic,
        test_SwitchIntegration_InferredType,
        test_ForIntegration_Basic,
        test_ForIntegration_Scoping,
        test_DeferIntegration_Basic,
        test_RejectionIntegration_ErrorUnion,
        test_RejectionIntegration_Optional,
        test_RejectionIntegration_TryExpression
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
