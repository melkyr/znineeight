#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_RecursiveSlice_MultiModule,
        test_RecursiveSlice_SelfReference
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
