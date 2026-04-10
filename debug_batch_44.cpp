#include "../src/bootstrap/bootstrap_all.cpp"
#include "test_utils.cpp"
#include "c89_validation/gcc_validator.cpp"
#include "c89_validation/msvc6_validator.cpp"
#include "integration/task225_2_tests.cpp"

extern "C" int main(int argc, char* argv[]) {
    printf("Running Task225_2_BracelessIfExpr...\n");
    if (test_Task225_2_BracelessIfExpr()) printf("BracelessIfExpr PASS\n");
    else printf("BracelessIfExpr FAIL\n");

    printf("Running Task225_2_PrintLowering...\n");
    if (test_Task225_2_PrintLowering()) printf("PrintLowering PASS\n");
    else printf("PrintLowering FAIL\n");

    printf("Running Task225_2_SwitchIfExpr...\n");
    if (test_Task225_2_SwitchIfExpr()) printf("SwitchIfExpr PASS\n");
    else printf("SwitchIfExpr FAIL\n");

    return 0;
}
