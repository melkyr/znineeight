#include "test_declarations.hpp"
#include "test_runner_main.hpp"

int main(int argc, char* argv[]) {
    bool (*tests[])() = {
        test_LiteralIntegration_IntegerDecimal,
        test_LiteralIntegration_IntegerHex,
        test_LiteralIntegration_IntegerUnsigned,
        test_LiteralIntegration_IntegerLong,
        test_LiteralIntegration_IntegerUnsignedLong,
        test_LiteralIntegration_FloatSimple,
        test_LiteralIntegration_FloatScientific,
        test_LiteralIntegration_FloatExplicitF64,
        test_LiteralIntegration_CharBasic,
        test_LiteralIntegration_CharEscape,
        test_LiteralIntegration_StringBasic,
        test_LiteralIntegration_StringEscape,
        test_LiteralIntegration_BoolTrue,
        test_LiteralIntegration_BoolFalse,
        test_LiteralIntegration_NullLiteral,
        test_LiteralIntegration_ExpressionStatement
    };

    return run_batch(argc, argv, tests, sizeof(tests) / sizeof(tests[0]));
}
