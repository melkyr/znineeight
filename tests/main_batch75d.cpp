#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_DoubleFree_ArenaLeakSuppression
    };
    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
