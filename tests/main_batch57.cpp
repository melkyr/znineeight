#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_Codegen_AnonymousUnion_Basic();
bool test_Codegen_AnonymousUnion_Nested();
bool test_Codegen_AnonymousStruct_Nested();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_AnonymousUnion_Basic,
        test_Codegen_AnonymousUnion_Nested,
        test_Codegen_AnonymousStruct_Nested
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
