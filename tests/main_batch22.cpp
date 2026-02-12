#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_c89_emitter_basic,
        test_c89_emitter_buffering,
        test_plat_file_raw_io
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
