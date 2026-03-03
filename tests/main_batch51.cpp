#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_UnionCapture_ForwardDeclaredStruct,
        test_UnionCapture_NestedUnion,
        test_UnionCapture_PointerToIncomplete,
        test_UnionCapture_InvalidIntegerCase
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
