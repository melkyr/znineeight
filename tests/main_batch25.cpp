#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_Codegen_Float_f64,
        test_Codegen_Float_f32,
        test_Codegen_Float_WholeNumber,
        test_Codegen_Float_Scientific,
        test_Codegen_Float_HexConversion
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
