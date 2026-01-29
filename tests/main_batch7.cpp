#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task142_ErrorFunctionDetection,
        test_Task142_ErrorFunctionRejection,
        test_Task143_TryExpressionDetection_Contexts,
        test_Task143_TryExpressionDetection_Nested,
        test_Task143_TryExpressionDetection_MultipleInStatement,
        test_CatchExpressionCatalogue_Basic,
        test_CatchExpressionCatalogue_Chaining,
        test_OrelseExpressionCatalogue_Basic,
        test_Task144_CatchExpressionDetection_Basic,
        test_Task144_CatchExpressionDetection_Chained,
        test_Task144_OrelseExpressionDetection,
        test_TypeChecker_VarDecl_Inferred_Crash,
        test_TypeChecker_VarDecl_Inferred_Loop,
        test_TypeChecker_VarDecl_Inferred_Multiple
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
