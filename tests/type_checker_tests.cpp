#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeCheckerValidDeclarations) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);

    // i32 declaration
    const char* source_i32 = "var x: i32 = 10;";
    ParserTestContext context_i32(source_i32, arena, interner);
    Parser parser_i32 = context_i32.getParser();
    ASTNode* root_i32 = parser_i32.parse();
    TypeChecker checker_i32(context_i32.getCompilationUnit());
    checker_i32.check(root_i32);
    ASSERT_FALSE(context_i32.getCompilationUnit().getErrorHandler().hasErrors());

    // i64 declaration
    const char* source_i64 = "var y: i64 = 3000000000;";
    ParserTestContext context_i64(source_i64, arena, interner);
    Parser parser_i64 = context_i64.getParser();
    ASTNode* root_i64 = parser_i64.parse();
    TypeChecker checker_i64(context_i64.getCompilationUnit());
    checker_i64.check(root_i64);
    ASSERT_FALSE(context_i64.getCompilationUnit().getErrorHandler().hasErrors());

    // bool declaration
    const char* source_bool = "var z: bool = true;";
    ParserTestContext context_bool(source_bool, arena, interner);
    Parser parser_bool = context_bool.getParser();
    ASTNode* root_bool = parser_bool.parse();
    TypeChecker checker_bool(context_bool.getCompilationUnit());
    checker_bool.check(root_bool);
    ASSERT_FALSE(context_bool.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerUndeclaredVariable) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "var x: i32 = y;";
    ParserTestContext context(source, arena, interner);
    Parser parser = context.getParser();
    ASTNode* root = parser.parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}

TEST_FUNC(TypeCheckerInvalidDeclarations) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "var x: i32 = \"hello\";";
    ParserTestContext context(source, arena, interner);
    Parser parser = context.getParser();
    ASTNode* root = parser.parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);
    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());

    return true;
}
