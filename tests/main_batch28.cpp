#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task168_MutualRecursion,
        test_Task168_IndirectCallSupport,
        test_Task168_GenericCallChain,
        test_Task168_BuiltinCall
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
