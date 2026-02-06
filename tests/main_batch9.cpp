#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_platform_alloc,
        test_platform_realloc,
        test_platform_string,
        test_platform_file,
        test_platform_print
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
