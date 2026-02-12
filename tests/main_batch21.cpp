#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_SizeOf_Primitive,
        test_SizeOf_Struct,
        test_SizeOf_Array,
        test_SizeOf_Pointer,
        test_SizeOf_Incomplete_Error,
        test_AlignOf_Primitive,
        test_AlignOf_Struct,
        test_PointerArithmetic_SizeOfUSize,
        test_PointerArithmetic_AlignOfISize
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
