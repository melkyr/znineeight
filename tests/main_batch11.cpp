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
        test_Codegen_StringAllC89Escapes,
        test_Codegen_Global_PubConst,
        test_Codegen_Global_PrivateConst,
        test_Codegen_Global_PubVar,
        test_Codegen_Global_PrivateVar,
        test_Codegen_Global_Array,
        test_Codegen_Global_Array_WithInit,
        test_Codegen_Global_Pointer,
        test_Codegen_Global_ConstPointer,
        test_Codegen_Global_KeywordCollision,
        test_Codegen_Global_LongName,
        test_Codegen_Global_PointerToGlobal,
        test_Codegen_Global_Arithmetic,
        test_Codegen_Global_Enum,
        test_Codegen_Global_Struct,
        test_Codegen_Global_AnonymousContainer_Error,
        test_Codegen_Global_NonConstantInit_Error
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
