#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Milestone4_Lexer_Tokens,
        test_Milestone4_Parser_AST,
        test_OptionalType_Creation,
        test_OptionalType_ToString,
        test_TypeChecker_OptionalType,
        test_NameMangler_Milestone4Types,
        test_CallSiteLookupTable_Basic,
        test_CallSiteLookupTable_Unresolved,
        test_TypeChecker_CallSiteRecording_Direct,
        test_TypeChecker_CallSiteRecording_Recursive,
        test_TypeChecker_CallSiteRecording_Generic,
        test_Task165_ForwardReference,
        test_Task165_BuiltinRejection,
        test_Task165_C89Incompatible,
        test_IndirectCall_Variable,
        test_IndirectCall_Member,
        test_IndirectCall_Array,
        test_IndirectCall_Returned,
        test_IndirectCall_Complex,
        test_ForwardReference_GlobalVariable,
        test_ForwardReference_MutualFunction,
        test_ForwardReference_StructType,
        test_Recursive_Factorial,
        test_Recursive_Mutual_Mangled,
        test_Recursive_Forward_Mangled,
        test_CallSyntax_AtImport,
        test_CallSyntax_AtImport_Rejection,
        test_CallSyntax_ComplexPostfix,
        test_CallSyntax_MethodCall,
        test_Task168_ComplexContexts,
        test_Task168_MutualRecursion,
        test_Task168_IndirectCallRejection,
        test_Task168_GenericCallChain,
        test_Task168_BuiltinCall
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
