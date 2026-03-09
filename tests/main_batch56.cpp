#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_UnionSliceLifting_Basic,
        test_UnionSliceLifting_Coercion,
        test_UnionSliceLifting_ManualConstruction
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
