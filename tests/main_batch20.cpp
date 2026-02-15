#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_PtrCast_Basic,
        test_PtrCast_ToConst,
        test_PtrCast_FromVoid,
        test_PtrCast_ToVoid,
        test_PtrCast_TargetNotPointer_Error,
        test_PtrCast_SourceNotPointer_Error,
        test_PtrCast_Nested,
        test_IntCast_Constant_Fold,
        test_IntCast_Constant_Overflow_Error,
        test_IntCast_Runtime,
        test_IntCast_Widening,
        test_IntCast_Bool,
        test_FloatCast_Constant_Fold,
        test_FloatCast_Runtime_Widening,
        test_FloatCast_Runtime_Narrowing,
        test_Cast_Invalid_Types_Error,
        test_Codegen_IntCast_SafeWidening,
        test_Codegen_IntCast_Narrowing,
        test_Codegen_IntCast_SignednessMismatch,
        test_Codegen_FloatCast_SafeWidening,
        test_Codegen_FloatCast_Narrowing
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
