#include "test_framework.hpp"
#include <cstdio>
#include <cstdlib>

// Parser tests (from test_parser_try_catch_revised.cpp)
bool test_Parser_Catch_WithBlock();
bool test_Parser_Try_Nested();
bool test_Parser_Catch_Precedence_Arithmetic();
bool test_Parser_Try_Precedence_Arithmetic();
bool test_Parser_ErrorUnion_Return();

// Integration tests (from task227_try_catch_tests.cpp)
bool test_Integration_Try_Defer_LIFO();
bool test_Integration_Nested_Try_Catch();
bool test_Integration_Try_In_Loop();
bool test_Integration_Catch_With_Complex_Block();
bool test_Integration_Catch_Basic();
bool test_TypeChecker_Try_Invalid();

int main() {
    int passed = 0;
    int failed = 0;

    printf("Running Batch 46 Parser Tests...\n");
    if (test_Parser_Catch_WithBlock()) passed++; else failed++;
    if (test_Parser_Try_Nested()) passed++; else failed++;
    if (test_Parser_Catch_Precedence_Arithmetic()) passed++; else failed++;
    if (test_Parser_Try_Precedence_Arithmetic()) passed++; else failed++;
    if (test_Parser_ErrorUnion_Return()) passed++; else failed++;

    printf("Running Batch 46 Integration Tests...\n");
    if (test_Integration_Try_Defer_LIFO()) passed++; else failed++;
    if (test_Integration_Nested_Try_Catch()) passed++; else failed++;
    if (test_Integration_Try_In_Loop()) passed++; else failed++;
    if (test_Integration_Catch_With_Complex_Block()) passed++; else failed++;
    if (test_Integration_Catch_Basic()) passed++; else failed++;
    if (test_TypeChecker_Try_Invalid()) passed++; else failed++;

    printf("Batch Results: %d passed, %d failed\n", passed, failed);
    return (failed == 0) ? 0 : 1;
}
