#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include <cstdio>

// Forward declarations for Group 4E: Pointer Arithmetic
TEST_FUNC(TypeCheckerVoidTests_PointerAddition);
TEST_FUNC(TypeChecker_PointerIntegerAddition);
TEST_FUNC(TypeChecker_IntegerPointerAddition);
TEST_FUNC(TypeChecker_PointerIntegerSubtraction);
TEST_FUNC(TypeChecker_PointerPointerSubtraction);
TEST_FUNC(TypeChecker_Invalid_PointerPointerAddition);
TEST_FUNC(TypeChecker_Invalid_PointerPointerSubtraction_DifferentTypes);
TEST_FUNC(TypeChecker_Invalid_PointerMultiplication);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerInteger);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_PointerPointer);
TEST_FUNC(TypeCheckerPointerOps_Arithmetic_InvalidOperations);

// Forward declarations for Group 4F: Binary & Logical Operations
TEST_FUNC(TypeCheckerBinaryOps_PointerArithmetic);
TEST_FUNC(TypeCheckerBinaryOps_NumericArithmetic);
TEST_FUNC(TypeCheckerBinaryOps_Comparison);
TEST_FUNC(TypeCheckerBinaryOps_Bitwise);
TEST_FUNC(TypeCheckerBinaryOps_Logical);
TEST_FUNC(TypeChecker_Bool_ComparisonOps);
TEST_FUNC(TypeChecker_Bool_LogicalOps);

// Forward declarations for Group 4G: Control Flow (if, while)
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithBooleanCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithIntegerCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithPointerCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithFloatCondition);
TEST_FUNC(TypeCheckerControlFlow_IfStatementWithVoidCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithBooleanCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithIntegerCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithPointerCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithFloatCondition);
TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithVoidCondition);

// Forward declarations for the single test
TEST_FUNC(Parser_Bugfix_HandlesExpressionStatement);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Parser_Bugfix_HandlesExpressionStatement,

        // Group 4E
        test_TypeCheckerVoidTests_PointerAddition,
        test_TypeChecker_PointerIntegerAddition,
        test_TypeChecker_IntegerPointerAddition,
        test_TypeChecker_PointerIntegerSubtraction,
        test_TypeChecker_PointerPointerSubtraction,
        test_TypeChecker_Invalid_PointerPointerAddition,
        test_TypeChecker_Invalid_PointerPointerSubtraction_DifferentTypes,
        test_TypeChecker_Invalid_PointerMultiplication,
        test_TypeCheckerPointerOps_Arithmetic_PointerInteger,
        test_TypeCheckerPointerOps_Arithmetic_PointerPointer,
        test_TypeCheckerPointerOps_Arithmetic_InvalidOperations,

        // Group 4F
        test_TypeCheckerBinaryOps_PointerArithmetic,
        test_TypeCheckerBinaryOps_NumericArithmetic,
        test_TypeCheckerBinaryOps_Comparison,
        test_TypeCheckerBinaryOps_Bitwise,
        test_TypeCheckerBinaryOps_Logical,
        test_TypeChecker_Bool_ComparisonOps,
        test_TypeChecker_Bool_LogicalOps,

        // Group 4G
        test_TypeCheckerControlFlow_IfStatementWithBooleanCondition,
        test_TypeCheckerControlFlow_IfStatementWithIntegerCondition,
        test_TypeCheckerControlFlow_IfStatementWithPointerCondition,
        test_TypeCheckerControlFlow_IfStatementWithFloatCondition,
        test_TypeCheckerControlFlow_IfStatementWithVoidCondition,
        test_TypeCheckerControlFlow_WhileStatementWithBooleanCondition,
        test_TypeCheckerControlFlow_WhileStatementWithIntegerCondition,
        test_TypeCheckerControlFlow_WhileStatementWithPointerCondition,
        test_TypeCheckerControlFlow_WhileStatementWithFloatCondition,
        test_TypeCheckerControlFlow_WhileStatementWithVoidCondition,
    };

    int passed = 0;
    int num_tests = sizeof(tests) / sizeof(tests[0]);

    for (int i = 0; i < num_tests; ++i) {
        if (tests[i]()) {
            passed++;
        }
    }

    printf("Passed %d/%d tests\n", passed, num_tests);
    return passed == num_tests ? 0 : 1;
}
