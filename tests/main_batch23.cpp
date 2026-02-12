#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_CVariableAllocator_Basic,
        test_CVariableAllocator_Keywords,
        test_CVariableAllocator_Truncation,
        test_CVariableAllocator_MangledReuse,
        test_CVariableAllocator_Generate,
        test_CVariableAllocator_Reset
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
