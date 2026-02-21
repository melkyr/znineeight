#include "test_runner_main.hpp"

// Forward declare the test functions from for_loop_tests.cpp
bool test_ForIntegration_Array();
bool test_ForIntegration_Slice();
bool test_ForIntegration_Range();
bool test_ForIntegration_IndexCapture();
bool test_ForIntegration_Labeled();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ForIntegration_Array,
        test_ForIntegration_Slice,
        test_ForIntegration_Range,
        test_ForIntegration_IndexCapture,
        test_ForIntegration_Labeled
    };
    return run_batch(argc, argv, tests, 5);
}
