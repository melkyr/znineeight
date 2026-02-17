#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_MultiModule_BasicCall();
bool test_MultiModule_StructUsage();
bool test_MultiModule_PrivateVisibility();
bool test_MultiModule_CircularImport();
bool test_MultiModule_RelativePath();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_MultiModule_BasicCall,
        test_MultiModule_StructUsage,
        test_MultiModule_PrivateVisibility,
        test_MultiModule_CircularImport,
        test_MultiModule_RelativePath
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
