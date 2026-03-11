#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "ast_lifter.hpp"
#include "codegen.hpp"
#include "mock_emitter.hpp"
#include "test_utils.hpp"


TEST_FUNC(RangeSwitch_InclusiveBasic) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "fn foo(x: i32) void { switch (x) { 1...3 => {}, else => {} } }";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    // Verify codegen (Mock)
    MockC89Emitter emitter;
    // We need to extract the switch statement from the AST
    // Block -> FnDecl -> Block -> Switch
    ASTNode* fn = (*root->as.block_stmt.statements)[0];
    ASTNode* body = fn->as.fn_decl->body;
    ASTNode* sw = (*body->as.block_stmt.statements)[0];

    std::string output = emitter.emitExpression(sw);
    ASSERT_TRUE(output.find("switch") != std::string::npos);
    return true;
}

TEST_FUNC(RangeSwitch_ExclusiveBasic) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "fn foo(x: i32) void { switch (x) { 1..3 => {}, else => {} } }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(RangeSwitch_MixedItems) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "fn foo(x: i32) void { switch (x) { 1, 3...5, 10 => {}, else => {} } }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(RangeSwitch_ErrorNonConstant) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "fn foo(x: i32, y: i32) void { switch (x) { 1...y => {}, else => {} } }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    ASSERT_EQ(ERR_NONCONSTANT_RANGE, unit.getErrorHandler().getErrors()[0].code);
    return true;
}

TEST_FUNC(RangeSwitch_ErrorTooLarge) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "fn foo(x: i32) void { switch (x) { 1...2000 => {}, else => {} } }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    ASSERT_EQ(ERR_RANGE_TOO_LARGE, unit.getErrorHandler().getErrors()[0].code);
    return true;
}

TEST_FUNC(RangeSwitch_ErrorEmpty) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "fn foo(x: i32) void { switch (x) { 5...3 => {}, else => {} } }";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_TRUE(unit.getErrorHandler().hasErrors());
    ASSERT_EQ(ERR_INVALID_RANGE, unit.getErrorHandler().getErrors()[0].code);
    return true;
}

TEST_FUNC(RangeSwitch_EnumRange) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source =
        "fn foo(x: i32) i32 {\n"
        "    return switch (x) {\n"
        "        1...2 => 1,\n"
        "        else => 0,\n"
        "    };\n"
        "}\n";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();

    TypeChecker checker(unit);
    checker.check(root);

    if (unit.getErrorHandler().hasErrors()) {
        unit.getErrorHandler().printErrors();
    }
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());
    return true;
}

TEST_FUNC(RangeSwitch_NestedControl) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source =
        "fn foo(x: i32, y: bool) void {\n"
        "    switch (x) {\n"
        "        1...5 => {\n"
        "            if (y) return;\n"
        "        },\n"
        "        else => {},\n"
        "    }\n"
        "}\n";
    u32 file_id = unit.addSource("test.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* root = parser->parse();
    TypeChecker checker(unit);
    checker.check(root);
    ASSERT_FALSE(unit.getErrorHandler().hasErrors());

    ControlFlowLifter lifter(&arena, &interner, &unit.getErrorHandler());
    lifter.lift(&unit);

    ASTNode* fn = (*root->as.block_stmt.statements)[0];
    ASTNode* body = fn->as.fn_decl->body;
    ASTNode* sw = (*body->as.block_stmt.statements)[0];

    ASSERT_EQ(NODE_SWITCH_STMT, sw->type);
    ASTNode* prong_body = (*sw->as.switch_stmt->prongs)[0]->body;
    ASSERT_EQ(NODE_BLOCK_STMT, prong_body->type);
    ASSERT_TRUE(prong_body->as.block_stmt.statements->length() > 0);

    return true;
}

#ifndef RETROZIG_TEST
int main() {
    int passed = 0;
    int total = 0;

    total++; if (test_RangeSwitch_InclusiveBasic()) passed++;
    total++; if (test_RangeSwitch_ExclusiveBasic()) passed++;
    total++; if (test_RangeSwitch_MixedItems()) passed++;
    total++; if (test_RangeSwitch_ErrorNonConstant()) passed++;
    total++; if (test_RangeSwitch_ErrorTooLarge()) passed++;
    total++; if (test_RangeSwitch_ErrorEmpty()) passed++;
    total++; if (test_RangeSwitch_EnumRange()) passed++;
    total++; if (test_RangeSwitch_NestedControl()) passed++;

    printf("Range Switch Integration Tests: %d/%d passed\n", passed, total);
    return (passed == total) ? 0 : 1;
}
#endif
