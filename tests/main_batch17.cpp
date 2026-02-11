#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_C89Validator_GCC_KnownGood,
        test_C89Validator_GCC_KnownBad,
        test_C89Validator_MSVC6_LongIdentifier,
        test_C89Validator_MSVC6_CppComment,
        test_C89Validator_MSVC6_LongLong,
        test_C89Validator_MSVC6_KnownGood
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
