#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_Codegen_Binary_Arithmetic();
bool test_Codegen_Binary_Comparison();
bool test_Codegen_Binary_Bitwise();
bool test_Codegen_Binary_CompoundAssignment();
bool test_Codegen_Binary_BitwiseCompoundAssignment();
bool test_Codegen_Binary_Wrapping();
bool test_Codegen_Binary_Logical_Keywords();

// Unary tests
bool test_Codegen_Unary_Negation();
bool test_Codegen_Unary_Plus();
bool test_Codegen_Unary_LogicalNot();
bool test_Codegen_Unary_BitwiseNot();
bool test_Codegen_Unary_AddressOf();
bool test_Codegen_Unary_Dereference();
bool test_Codegen_Unary_Nested();
bool test_Codegen_Unary_Mixed();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_Binary_Arithmetic,
        test_Codegen_Binary_Comparison,
        test_Codegen_Binary_Bitwise,
        test_Codegen_Binary_CompoundAssignment,
        test_Codegen_Binary_BitwiseCompoundAssignment,
        test_Codegen_Binary_Wrapping,
        test_Codegen_Binary_Logical_Keywords,
        test_Codegen_Unary_Negation,
        test_Codegen_Unary_Plus,
        test_Codegen_Unary_LogicalNot,
        test_Codegen_Unary_BitwiseNot,
        test_Codegen_Unary_AddressOf,
        test_Codegen_Unary_Dereference,
        test_Codegen_Unary_Nested,
        test_Codegen_Unary_Mixed
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
