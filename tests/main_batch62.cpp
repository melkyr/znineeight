#include "test_declarations.hpp"
#include "test_runner_main.hpp"

TEST_FUNC(IssueSegfaultReturn);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_IssueSegfaultReturn
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
