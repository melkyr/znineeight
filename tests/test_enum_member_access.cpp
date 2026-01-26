#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include <cstring>

TEST_FUNC(TypeCheckerEnum_MemberAccess) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const Color = enum { Red, Green, Blue };\n"
        "const my_color = Color.Green;\n";

    u32 file_id = unit.getSourceManager().addFile("test.zig", source, strlen(source));
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    // Verify my_color's type
    Symbol* sym = unit.getSymbolTable().lookup("my_color");
    ASSERT_TRUE(sym != NULL);
    ASSERT_TRUE(sym->symbol_type != NULL);
    ASSERT_EQ(sym->symbol_type->kind, TYPE_ENUM);

    return true;
}

TEST_FUNC(TypeCheckerEnum_InvalidMemberAccess) {
    const char* source =
        "const Color = enum { Red, Green };\n"
        "const x = Color.Blue;\n";

    // This should fail type checking
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnum_ImplicitConversion) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const Color = enum { Red, Green, Blue };\n"
        "const x: i32 = Color.Red;\n";

    u32 file_id = unit.getSourceManager().addFile("test.zig", source, strlen(source));
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeCheckerEnum_DuplicateMember) {
    const char* source = "const Color = enum { Red, Green, Red };";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeCheckerEnum_AutoIncrement) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const Status = enum { Ok = 0, Error = 10, Unknown, Fatal };\n"
        "const u = Status.Unknown;\n"
        "const f = Status.Fatal;\n";

    u32 file_id = unit.getSourceManager().addFile("test.zig", source, strlen(source));
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    // In my implementation, members are stored in a DynamicArray in EnumDetails.
    // I need to find the Enum type first.
    Symbol* sym_status = unit.getSymbolTable().lookup("Status");
    ASSERT_TRUE(sym_status != NULL);
    Type* status_type = sym_status->symbol_type;
    ASSERT_EQ(status_type->kind, TYPE_ENUM);

    DynamicArray<EnumMember>* members = status_type->as.enum_details.members;
    ASSERT_EQ(members->length(), 4);
    ASSERT_EQ((*members)[0].value, 0);
    ASSERT_EQ((*members)[1].value, 10);
    ASSERT_EQ((*members)[2].value, 11);
    ASSERT_EQ((*members)[3].value, 12);

    return true;
}

TEST_FUNC(TypeCheckerEnum_Switch) {
    ArenaAllocator arena(16384);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    const char* source =
        "const Color = enum { Red, Green, Blue };\n"
        "fn foo(c: Color) -> i32 {\n"
        "    return switch (c) {\n"
        "        Color.Red => 1,\n"
        "        Color.Green => 2,\n"
        "        else => 3,\n"
        "    };\n"
        "}\n";

    u32 file_id = unit.getSourceManager().addFile("test.zig", source, strlen(source));
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}
