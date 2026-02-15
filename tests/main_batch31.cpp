#include "test_declarations.hpp"
#include "test_runner_main.hpp"

// Forward declarations
bool test_Codegen_Array_Simple();
bool test_Codegen_Array_MultiDim();
bool test_Codegen_Array_Pointer();
bool test_Codegen_Array_Const();
bool test_Codegen_Array_ExpressionIndex();
bool test_Codegen_Array_NestedMember();
bool test_Codegen_Array_OOB_Error();
bool test_Codegen_Array_NonIntegerIndex_Error();
bool test_Codegen_Array_NonArrayBase_Error();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_Array_Simple,
        test_Codegen_Array_MultiDim,
        test_Codegen_Array_Pointer,
        test_Codegen_Array_Const,
        test_Codegen_Array_ExpressionIndex,
        test_Codegen_Array_NestedMember,
        test_Codegen_Array_OOB_Error,
        test_Codegen_Array_NonIntegerIndex_Error,
        test_Codegen_Array_NonArrayBase_Error
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
