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

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_Binary_Arithmetic,
        test_Codegen_Binary_Comparison,
        test_Codegen_Binary_Bitwise,
        test_Codegen_Binary_CompoundAssignment,
        test_Codegen_Binary_BitwiseCompoundAssignment,
        test_Codegen_Binary_Wrapping,
        test_Codegen_Binary_Logical_Keywords
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
