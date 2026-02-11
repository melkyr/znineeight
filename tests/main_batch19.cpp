#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Task183_USizeISizeSupported,
        test_Task182_ArenaAllocReturnsVoidPtr,
        test_Task182_ImplicitVoidPtrToTypedPtrAssignment,
        test_Task182_ImplicitVoidPtrToTypedPtrArgument,
        test_Task182_ImplicitVoidPtrToTypedPtrReturn,
        test_Task182_ConstCorrectness_AddConst,
        test_Task182_ConstCorrectness_PreserveConst,
        test_Task182_ConstCorrectness_DiscardConst_REJECT,
        test_Task182_NonC89Target_REJECT,
        test_PointerArithmetic_PtrPlusUSize,
        test_PointerArithmetic_USizePlusPtr,
        test_PointerArithmetic_PtrMinusUSize,
        test_PointerArithmetic_PtrMinusPtr,
        test_PointerArithmetic_PtrPlusISize,
        test_PointerArithmetic_SizeOfUSize,
        test_PointerArithmetic_AlignOfISize,
        test_PointerArithmetic_PtrPlusPtr_Error,
        test_PointerArithmetic_PtrMulInt_Error,
        test_PointerArithmetic_DiffDifferentTypes_Error,
        test_IntegerWidening_Args_Signed,
        test_IntegerWidening_Args_ISize,
        test_IntegerNarrowing_Args_Error,
        test_IntegerNarrowing_ISize_Error,
        test_IntegerWidening_Args_Unsigned,
        test_IntegerWidening_Args_USize
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
