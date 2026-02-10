#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_IfStatementIntegration_BoolCondition,
        test_IfStatementIntegration_IntCondition,
        test_IfStatementIntegration_PointerCondition,
        test_IfStatementIntegration_IfElse,
        test_IfStatementIntegration_ElseIfChain,
        test_IfStatementIntegration_NestedIf,
        test_IfStatementIntegration_LogicalAnd,
        test_IfStatementIntegration_LogicalOr,
        test_IfStatementIntegration_LogicalNot,
        test_IfStatementIntegration_EmptyBlocks,
        test_IfStatementIntegration_ReturnFromBranches,
        test_IfStatementIntegration_RejectFloatCondition,
        test_IfStatementIntegration_RejectBracelessIf
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
