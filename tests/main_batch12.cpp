#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_Local_Simple,
        test_Codegen_Local_AfterStatement,
        test_Codegen_Local_Const,
        test_Codegen_Local_Undefined,
        test_Codegen_Local_Shadowing,
        test_Codegen_Local_IfStatement,
        test_Codegen_Local_WhileLoop,
        test_Codegen_Local_Return,
        test_Codegen_Local_MultipleBlocks,
        test_Codegen_Fn_Simple,
        test_Codegen_Fn_Public,
        test_Codegen_Fn_Params,
        test_Codegen_Fn_Pointers,
        test_Codegen_Fn_Call,
        test_Codegen_Fn_KeywordParam,
        test_Codegen_Fn_MangledCall,
        test_Codegen_Fn_StructReturn,
        test_Codegen_Fn_Extern,
        test_Codegen_Fn_Export,
        test_Codegen_Fn_LongName,
        test_Codegen_Fn_RejectArrayReturn
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
