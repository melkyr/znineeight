#include "test_runner_main.hpp"
#include <cstdio>

extern bool test_BugVerify_ImplicitUnwrapErrorUnion();
extern bool test_BugVerify_ImplicitUnwrapOptional();
extern bool test_BugVerify_SwitchMissingCommaBlock();
extern bool test_BugVerify_SwitchExprMissingElse();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_BugVerify_ImplicitUnwrapErrorUnion,
        test_BugVerify_ImplicitUnwrapOptional,
        test_BugVerify_SwitchMissingCommaBlock,
        test_BugVerify_SwitchExprMissingElse
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
