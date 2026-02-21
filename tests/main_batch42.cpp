#include "test_runner_main.hpp"

// From for_tests.cpp
bool test_ForIntegration_Basic();
bool test_ForIntegration_InvalidIterable();
bool test_ForIntegration_ImmutableCapture();
bool test_ForIntegration_DiscardCapture();
bool test_ForIntegration_Scoping();

// From param_tests.cpp
bool test_ParamIntegration_Immutable();
bool test_ParamIntegration_MutablePointer();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ForIntegration_Basic,
        test_ForIntegration_InvalidIterable,
        test_ForIntegration_ImmutableCapture,
        test_ForIntegration_DiscardCapture,
        test_ForIntegration_Scoping,
        test_ParamIntegration_Immutable,
        test_ParamIntegration_MutablePointer
    };
    return run_batch(argc, argv, tests, 7);
}
