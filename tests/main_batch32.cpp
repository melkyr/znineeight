#include "test_declarations.hpp"
#include "test_runner_main.hpp"

TEST_FUNC(EndToEnd_HelloWorld);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_EndToEnd_HelloWorld,
        test_EndToEnd_PrimeNumbers
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
