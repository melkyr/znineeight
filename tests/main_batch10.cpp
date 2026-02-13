#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_c89_emitter_basic,
        test_c89_emitter_buffering,
        test_plat_file_raw_io,
        test_CVariableAllocator_Basic,
        test_CVariableAllocator_Keywords,
        test_CVariableAllocator_Truncation,
        test_CVariableAllocator_MangledReuse,
        test_CVariableAllocator_Generate,
        test_CVariableAllocator_Reset,
        test_Codegen_Int_i32,
        test_Codegen_Int_u32,
        test_Codegen_Int_i64,
        test_Codegen_Int_u64,
        test_Codegen_Int_usize,
        test_Codegen_Int_u8,
        test_Codegen_Int_HexToDecimal,
        test_Codegen_Int_LargeU64,
        test_Codegen_Float_f64,
        test_Codegen_Float_f32,
        test_Codegen_Float_WholeNumber,
        test_Codegen_Float_Scientific,
        test_Codegen_Float_HexConversion
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
