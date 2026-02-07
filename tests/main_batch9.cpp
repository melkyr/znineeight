#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_platform_alloc,
        test_platform_realloc,
        test_platform_string,
        test_platform_file,
        test_platform_print,
        test_Task156_ModuleDerivation,
        test_Task156_ASTNodeModule,
        test_Task156_EnhancedGenericDetection,
        test_Task156_InternalErrorCode,
        test_lex_decrement_operator,
        test_lex_decrement_mixed,
        test_lex_pipe_pipe_operator,
        test_GenericCatalogue_ImplicitInstantiation,
        test_TypeChecker_ImplicitGenericDetection,
        test_TypeChecker_AnytypeImplicitDetection
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
