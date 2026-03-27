#include "test_runner_main.hpp"

extern bool test_ASTLifter_ComplexLvalue_Member();
extern bool test_ASTLifter_ComplexLvalue_Array();
extern bool test_ASTLifter_EvaluationOrder();
extern bool test_ASTLifter_CompoundAssignment_Complex();

#ifndef Z98_TEST
int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ASTLifter_ComplexLvalue_Member,
        test_ASTLifter_ComplexLvalue_Array,
        test_ASTLifter_EvaluationOrder,
        test_ASTLifter_CompoundAssignment_Complex
    };
    return run_batch(argc, argv, tests, 4);
}
#endif
