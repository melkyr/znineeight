#include "test_runner_main.hpp"

// Forward declarations
bool test_lex_decrement_operator();
bool test_lex_decrement_mixed();
bool test_lex_pipe_pipe_operator();
bool test_GenericCatalogue_ImplicitInstantiation();
bool test_GenericCatalogue_Deduplication();
bool test_TypeChecker_ImplicitGenericDetection();
bool test_TypeChecker_AnytypeImplicitDetection();

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_lex_decrement_operator,
        test_lex_decrement_mixed,
        test_lex_pipe_pipe_operator,
        test_GenericCatalogue_ImplicitInstantiation,
        test_GenericCatalogue_Deduplication,
        test_TypeChecker_ImplicitGenericDetection,
        test_TypeChecker_AnytypeImplicitDetection
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
