#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_ImportResolution_Basic();
bool test_ImportResolution_IncludePath();
bool test_ImportResolution_DefaultLib();
bool test_ImportResolution_PrecedenceLocal();
bool test_ImportResolution_NotFound();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ImportResolution_Basic,
        test_ImportResolution_IncludePath,
        test_ImportResolution_DefaultLib,
        test_ImportResolution_PrecedenceLocal,
        test_ImportResolution_NotFound
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
