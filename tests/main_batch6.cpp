#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_TypeChecker_StructDeclaration_Valid,
        test_TypeChecker_StructDeclaration_DuplicateField,
        test_TypeChecker_StructInitialization_Valid,
        test_TypeChecker_MemberAccess_Valid,
        test_TypeChecker_MemberAccess_InvalidField,
        test_TypeChecker_StructInitialization_MissingField,
        test_TypeChecker_StructInitialization_ExtraField,
        test_TypeChecker_StructInitialization_TypeMismatch,
        test_TypeChecker_StructLayout_Verification,
        test_TypeChecker_UnionDeclaration_DuplicateField
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
