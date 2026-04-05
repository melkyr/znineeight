#include "test_runner_main.hpp"

extern bool test_Aggregate_ArrayLiteral_Coercion();
extern bool test_Aggregate_TupleLiteral_Coercion();
extern bool test_Aggregate_UnionLiteral_Coercion();
extern bool test_Aggregate_Nested_Mixed();
extern bool test_Aggregate_Error_NoContext();
extern bool test_Aggregate_Array_SizeMismatch();

bool (*tests[])() = {
    test_Aggregate_ArrayLiteral_Coercion,
    test_Aggregate_TupleLiteral_Coercion,
    test_Aggregate_UnionLiteral_Coercion,
    test_Aggregate_Nested_Mixed,
    test_Aggregate_Error_NoContext,
    test_Aggregate_Array_SizeMismatch
};

int main(int argc, char* argv[]) {
    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
