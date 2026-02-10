#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_WhileLoopIntegration_BoolCondition,
        test_WhileLoopIntegration_IntCondition,
        test_WhileLoopIntegration_PointerCondition,
        test_WhileLoopIntegration_WithBreak,
        test_WhileLoopIntegration_WithContinue,
        test_WhileLoopIntegration_NestedWhile,
        test_WhileLoopIntegration_Scoping,
        test_WhileLoopIntegration_ComplexCondition,
        test_WhileLoopIntegration_RejectFloatCondition,
        test_WhileLoopIntegration_RejectBracelessWhile,
        test_WhileLoopIntegration_EmptyWhileBlock
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
