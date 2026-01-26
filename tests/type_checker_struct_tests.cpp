#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_StructDeclaration_Valid) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source = "const Point = struct { x: i32, y: i32 };";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_StructDeclaration_DuplicateField) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source = "const S = struct { x: i32, x: bool };";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_StructLayout_Verification) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source = "const S = struct { a: u8, b: i32, c: u8 };";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    Symbol* sym = context.getCompilationUnit().getSymbolTable().lookup("S");
    ASSERT_TRUE(sym != NULL);
    Type* type = sym->symbol_type;
    ASSERT_EQ(type->kind, TYPE_STRUCT);

    DynamicArray<StructField>* fields = type->as.struct_details.fields;
    ASSERT_EQ(fields->length(), 3);

    // a: u8, offset 0, size 1
    ASSERT_EQ((*fields)[0].offset, 0);
    ASSERT_EQ((*fields)[0].size, 1);

    // b: i32, offset should be 4 (due to alignment of i32)
    ASSERT_EQ((*fields)[1].offset, 4);
    ASSERT_EQ((*fields)[1].size, 4);

    // c: u8, offset should be 8
    ASSERT_EQ((*fields)[2].offset, 8);
    ASSERT_EQ((*fields)[2].size, 1);

    // Total size should be aligned to max_alignment (4), so 12.
    ASSERT_EQ(type->size, 12);
    ASSERT_EQ(type->alignment, 4);

    return true;
}

TEST_FUNC(TypeChecker_UnionDeclaration_DuplicateField) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source = "const U = union { x: i32, x: bool };";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_StructInitialization_Valid) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn main() -> void {\n"
        "    var p: Point = Point { .x = 10, .y = 20 };\n"
        "}";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_MemberAccess_Valid) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn main() -> void {\n"
        "    var p: Point = Point { .x = 10, .y = 20 };\n"
        "    var x_val: i32 = p.x;\n"
        "}";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_FALSE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_MemberAccess_InvalidField) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn main() -> void {\n"
        "    var p: Point = Point { .x = 10, .y = 20 };\n"
        "    var z_val: i32 = p.z;\n"
        "}";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_StructInitialization_MissingField) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn main() -> void {\n"
        "    var p: Point = Point { .x = 10 };\n"
        "}";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_StructInitialization_ExtraField) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn main() -> void {\n"
        "    var p: Point = Point { .x = 10, .y = 20, .z = 30 };\n"
        "}";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(TypeChecker_StructInitialization_TypeMismatch) {
    ArenaAllocator arena(32768);
    StringInterner interner(arena);

    const char* source =
        "const Point = struct { x: i32, y: i32 };\n"
        "fn main() -> void {\n"
        "    var p: Point = Point { .x = 10, .y = true };\n"
        "}";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();
    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    ASSERT_TRUE(context.getCompilationUnit().getErrorHandler().hasErrors());
    return true;
}
