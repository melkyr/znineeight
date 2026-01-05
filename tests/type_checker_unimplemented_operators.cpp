#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "error_handler.hpp"
#include <cstring>

// Helper to check for a specific error message
static bool find_error_message(const DynamicArray<ErrorReport>& errors, const char* expected_msg) {
    for (size_t i = 0; i < errors.length(); ++i) {
        if (strcmp(errors[i].message, expected_msg) == 0) {
            return true;
        }
    }
    return false;
}

TEST_FUNC(TypeChecker_UnimplementedBitwiseOperator) {
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    TypeChecker checker(unit);

    // This expression is syntactically valid but uses a bitwise operator
    // that is not yet implemented in the type checker.
    const char* source = "fn test_fn() { var x: i32 = 1 & 2; }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser parser = unit.createParser(file_id);
    ASTNode* ast = parser.parse();

    // We expect the type checker to report a specific error.
    checker.check(ast);

    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    ASSERT_TRUE(find_error_message(unit.getErrorHandler().getErrors(), "Operator '&' is not implemented yet."));

    return true;
}
