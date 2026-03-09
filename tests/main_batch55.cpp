#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_ASTLifter_BasicIf,
        test_ASTLifter_Nested,
        test_ASTLifter_ComplexAssignment,
        test_ASTLifter_CompoundAssignment,
        test_ASTLifter_Unified,
        test_ASTLifter_MemoryStressTest
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
