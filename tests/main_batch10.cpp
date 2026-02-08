#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_simple_mangling,
        test_generic_mangling,
        test_multiple_generic_mangling,
        test_c_keyword_collision,
        test_reserved_name_collision,
        test_length_limit,
        test_determinism
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
