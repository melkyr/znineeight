#include "test_runner_main.hpp"

TEST_FUNC(SwitchProng_ReturnNoSemicolon);
TEST_FUNC(SwitchProng_BlockMandatoryComma);
TEST_FUNC(SwitchProng_ExprRequiredCommaFail);
TEST_FUNC(SwitchProng_LastProngOptionalComma);
TEST_FUNC(SwitchProng_DeclRequiresBlockFail);

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_SwitchProng_ReturnNoSemicolon,
        test_SwitchProng_BlockMandatoryComma,
        test_SwitchProng_ExprRequiredCommaFail,
        test_SwitchProng_LastProngOptionalComma,
        test_SwitchProng_DeclRequiresBlockFail
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
