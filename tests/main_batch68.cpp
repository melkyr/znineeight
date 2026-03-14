#include "test_runner_main.hpp"

/* Forward declarations */
bool test_StringLiteral_To_ManyPtr();
bool test_StringLiteral_To_Slice();
bool test_StringLiteral_BackwardCompat();
bool test_PtrToArray_To_ManyPtr();
bool test_PtrToArray_To_Slice();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_StringLiteral_To_ManyPtr,
        test_StringLiteral_To_Slice,
        test_StringLiteral_BackwardCompat,
        test_PtrToArray_To_ManyPtr,
        test_PtrToArray_To_Slice
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
