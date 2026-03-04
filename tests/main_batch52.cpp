#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task9_8_StringLiteralCoercion,
        test_Task9_8_ImplicitReturnErrorVoid,
        test_Task9_8_WhileContinueExpr
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
