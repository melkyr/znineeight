#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_Pointer_Pointer_Decl();
bool test_Pointer_Pointer_Dereference();
bool test_Pointer_Pointer_Triple();
bool test_Pointer_Pointer_Param_Return();
bool test_Pointer_Pointer_Const_Ignored();
bool test_Pointer_Pointer_Global_Emission();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Pointer_Pointer_Decl,
        test_Pointer_Pointer_Dereference,
        test_Pointer_Pointer_Triple,
        test_Pointer_Pointer_Param_Return,
        test_Pointer_Pointer_Const_Ignored,
        test_Pointer_Pointer_Global_Emission
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
