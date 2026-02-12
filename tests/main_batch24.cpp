#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_Int_i32,
        test_Codegen_Int_u32,
        test_Codegen_Int_i64,
        test_Codegen_Int_u64,
        test_Codegen_Int_usize,
        test_Codegen_Int_u8,
        test_Codegen_Int_HexToDecimal,
        test_Codegen_Int_LargeU64
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
