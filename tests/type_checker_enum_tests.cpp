#include "test_framework.hpp"
#include "test_utils.hpp"

TEST_FUNC(TypeCheckerEnumTests_SignedIntegerOverflow) {
    const char* source = "const x: enum(i8) { A = 128 };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnumTests_SignedIntegerUnderflow) {
    const char* source = "const x: enum(i8) { A = -129 };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnumTests_UnsignedIntegerOverflow) {
    const char* source = "const x: enum(u8) { A = 256 };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnumTests_NegativeValueInUnsignedEnum) {
    const char* source = "const x: enum(u8) { A = -1 };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnumTests_AutoIncrementOverflow) {
    const char* source = "const x: enum(u8) { Y = 254, Z, Over };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnumTests_AutoIncrementSignedOverflow) {
    const char* source = "const x: enum(i8) { Y = 126, Z, Over };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnumTests_ValidValues) {
    const char* source =
        "const x: enum(i8) {"
        "    Min = -128,"
        "    Max = 127"
        "};"
        "const y: enum(u8) {"
        "    Min = 0,"
        "    Max = 255"
        "};";
    // This should NOT abort
    ASSERT_FALSE(expect_type_checker_abort(source));
    return true;
}
