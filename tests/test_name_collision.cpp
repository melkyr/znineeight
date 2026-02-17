#include "test_framework.hpp"
#include "test_utils.hpp"
#include "name_collision_detector.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"

TEST_FUNC(FunctionNameCollisionSameScope) {
    const char* source =
        "fn foo() void {}\n"
        "fn foo() i32 { return 0; }\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    NameCollisionDetector checker(unit);
    checker.check(ast);

    ASSERT_TRUE(checker.hasCollisions());
    ASSERT_EQ(1, checker.getCollisionCount());
    return true;
}

TEST_FUNC(FunctionVariableCollisionSameScope) {
    const char* source =
        "fn foo() void {}\n"
        "var foo: i32 = 5;\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    NameCollisionDetector checker(unit);
    checker.check(ast);

    ASSERT_TRUE(checker.hasCollisions());
    return true;
}

TEST_FUNC(ShadowingAllowed) {
    const char* source =
        "fn foo() void {}\n"
        "fn bar() void {\n"
        "    const foo: i32 = 5;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();
    ASSERT_TRUE(ast != NULL);

    NameCollisionDetector checker(unit);
    checker.check(ast);

    ASSERT_FALSE(checker.hasCollisions());
    return true;
}
