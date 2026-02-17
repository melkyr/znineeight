#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

static bool typeCheckTest(const char* source) {
    ArenaAllocator arena(262144);
    StringInterner interner(arena);
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    if (!root) {
        return false; // Parser error
    }

    type_checker.check(root);

    return !ctx.getCompilationUnit().getErrorHandler().hasErrors();
}

TEST_FUNC(TypeCheckerControlFlow_IfStatementWithBooleanCondition) {
    // Test that an if statement with a boolean condition is accepted.
    const char* source = "fn main() -> void { if (true) {} }";
    ASSERT_TRUE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_IfStatementWithIntegerCondition) {
    // Test that an if statement with an integer condition is accepted.
    const char* source = "fn main() -> void { if (1) {} }";
    ASSERT_TRUE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_IfStatementWithPointerCondition) {
    // Test that an if statement with a pointer condition is accepted.
    const char* source = "fn main() -> void { var x: i32 = 0; if (&x) {} }";
    ASSERT_TRUE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_IfStatementWithFloatCondition) {
    // Test that an if statement with a float condition is rejected.
    const char* source = "fn main() -> void { if (1.0) {} }";
    ASSERT_FALSE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_IfStatementWithVoidCondition) {
    // Test that an if statement with a void condition is rejected.
    const char* source = "fn my_func() -> void {} fn main() -> void { if (my_func()) {} }";
    ASSERT_FALSE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithBooleanCondition) {
    // Test that a while statement with a boolean condition is accepted.
    const char* source = "fn main() -> void { while (true) {} }";
    ASSERT_TRUE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithIntegerCondition) {
    // Test that a while statement with an integer condition is accepted.
    const char* source = "fn main() -> void { while (1) {} }";
    ASSERT_TRUE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithPointerCondition) {
    // Test that a while statement with a pointer condition is accepted.
    const char* source = "fn main() -> void { var x: i32 = 0; while (&x) {} }";
    ASSERT_TRUE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithFloatCondition) {
    // Test that a while statement with a float condition is rejected.
    const char* source = "fn main() -> void { while (1.0) {} }";
    ASSERT_FALSE(typeCheckTest(source));
    return true;
}

TEST_FUNC(TypeCheckerControlFlow_WhileStatementWithVoidCondition) {
    // Test that a while statement with a void condition is rejected.
    const char* source = "fn my_func() -> void {} fn main() -> void { while (my_func()) {} }";
    ASSERT_FALSE(typeCheckTest(source));
    return true;
}
