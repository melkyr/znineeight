#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Import_Simple,
        test_Import_Circular,
        test_Import_Missing
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
