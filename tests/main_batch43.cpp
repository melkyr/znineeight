#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_SwitchNoreturn_BasicDivergence,
        test_SwitchNoreturn_AllDivergent,
        test_SwitchNoreturn_BreakInProng,
        test_SwitchNoreturn_LabeledBreakInProng,
        test_SwitchNoreturn_MixedTypesError,
        test_SwitchNoreturn_VariableNoreturnError,
        test_SwitchNoreturn_BlockProng
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
