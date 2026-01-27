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
        test_TypeChecker_UnionDeclaration_DuplicateField,
        test_TypeCheckerEnum_MemberAccess,
        test_TypeCheckerEnum_InvalidMemberAccess,
        test_TypeCheckerEnum_ImplicitConversion,
        test_TypeCheckerEnum_Switch,
        test_TypeCheckerEnum_DuplicateMember,
        test_TypeCheckerEnum_AutoIncrement,
        test_C89Rejection_ErrorUnionType_FnReturn,
        test_C89Rejection_OptionalType_VarDecl,
        test_C89Rejection_ErrorUnionType_Param,
        test_C89Rejection_ErrorUnionType_StructField,
        test_C89Rejection_NestedErrorUnionType,
        test_Task136_ErrorSet_Catalogue,
        test_Task136_ErrorSet_Rejection,
        test_Task136_ErrorSetMerge_Rejection,
        test_Task136_Import_Rejection,
        test_C89Rejection_ExplicitGeneric,
        test_C89Rejection_ImplicitGeneric,
        test_GenericCatalogue_TracksExplicit,
        test_GenericCatalogue_TracksImplicit,
        test_C89Rejection_ComptimeValueParam,
        test_GenericCatalogue_Deduplication,
        test_Task142_ErrorFunctionDetection,
        test_Task142_ErrorFunctionRejection
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
