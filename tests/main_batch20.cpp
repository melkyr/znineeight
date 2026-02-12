#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_PtrCast_Basic,
        test_PtrCast_ToConst,
        test_PtrCast_FromVoid,
        test_PtrCast_ToVoid,
        test_PtrCast_TargetNotPointer_Error,
        test_PtrCast_SourceNotPointer_Error,
        test_PtrCast_Nested
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
