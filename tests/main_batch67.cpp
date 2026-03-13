#include "test_runner_main.hpp"

/* Forward declarations */
bool test_UnionTagAccess_Basic();
bool test_UnionTagAccess_Alias();
bool test_UnionTagAccess_Imported();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_UnionTagAccess_Basic,
        test_UnionTagAccess_Alias,
        test_UnionTagAccess_Imported
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
