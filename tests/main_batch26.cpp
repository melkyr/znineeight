#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_StringSimple,
        test_Codegen_StringEscape,
        test_Codegen_StringQuotes,
        test_Codegen_StringOctal,
        test_Codegen_CharSimple,
        test_Codegen_CharEscape,
        test_Codegen_CharSingleQuote,
        test_Codegen_CharDoubleQuote,
        test_Codegen_CharOctal,
        test_Codegen_StringSymbolicEscapes,
        test_Codegen_StringAllC89Escapes
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
