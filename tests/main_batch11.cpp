#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Milestone4_Lexer_Tokens,
        test_Milestone4_Parser_AST,
        test_OptionalType_Creation,
        test_OptionalType_ToString,
        test_TypeChecker_OptionalType,
        test_NameMangler_Milestone4Types
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
