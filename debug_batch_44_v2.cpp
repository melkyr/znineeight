#include "../src/bootstrap/bootstrap_all.cpp"
#include "test_utils.cpp"
#include "c89_validation/gcc_validator.cpp"
#include "c89_validation/msvc6_validator.cpp"
#include "integration/task225_2_tests.cpp"

extern "C" int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    if (argv[1][0] == '1') test_Task225_2_BracelessIfExpr();
    if (argv[1][0] == '2') test_Task225_2_PrintLowering();
    if (argv[1][0] == '3') test_Task225_2_SwitchIfExpr();
    return 0;
}
