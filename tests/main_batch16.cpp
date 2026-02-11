#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_PointerIntegration_AddressOfDereference,
        test_PointerIntegration_DereferenceExpression,
        test_PointerIntegration_PointerArithmeticAdd,
        test_PointerIntegration_PointerArithmeticSub,
        test_PointerIntegration_NullLiteral,
        test_PointerIntegration_NullComparison,
        test_PointerIntegration_PointerToStruct,
        test_PointerIntegration_VoidPointerAssignment,
        test_PointerIntegration_ConstAdding,
        test_PointerIntegration_ReturnLocalAddressError,
        test_PointerIntegration_DereferenceNullError,
        test_PointerIntegration_PointerPlusPointerError,
        test_PointerIntegration_DereferenceNonPointerError,
        test_PointerIntegration_AddressOfNonLValue,
        test_PointerIntegration_IncompatiblePointerAssignment
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
