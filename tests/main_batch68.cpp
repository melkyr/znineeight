#include "test_runner_main.hpp"

/* Forward declarations */
bool test_StringLiteral_To_ManyItemPointer();
bool test_StringLiteral_To_Slice();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_StringLiteral_To_ManyItemPointer,
        test_StringLiteral_To_Slice
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
