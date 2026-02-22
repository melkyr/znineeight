#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task225_2_BracelessIfExpr,
        test_Task225_2_PrintLowering,
        test_Task225_2_SwitchIfExpr
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
