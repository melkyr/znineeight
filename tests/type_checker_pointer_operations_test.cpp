#include "../src/include/test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_Dereference_Invalid_NonPointer) {
    const char* source = "fn main() -> i32 { var x: i32 = 10; return *x; }";
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* p = comp_unit.createParser(file_id);
    ASTNode* root = p->parse();
    TypeChecker tc(comp_unit);
    tc.check(root);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    ASSERT_EQ(1, comp_unit.getErrorHandler().getErrors().length());
    ASSERT_EQ(ERR_TYPE_MISMATCH, comp_unit.getErrorHandler().getErrors()[0].code);
    return true;
}

TEST_FUNC(TypeChecker_Dereference_VoidPointer) {
    const char* source = "fn main() { var p: *void = null; var y = *p; }";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_Dereference_NullLiteral) {
    const char* source = "fn main() { var y = *null; }";
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* p = comp_unit.createParser(file_id);
    ASTNode* root = p->parse();
    TypeChecker tc(comp_unit);
    tc.check(root);
    ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
    ASSERT_EQ(1, comp_unit.getErrorHandler().getErrors().length());
    ASSERT_EQ(ERR_TYPE_MISMATCH, comp_unit.getErrorHandler().getErrors()[0].code);
    return true;
}

TEST_FUNC(TypeChecker_Dereference_ValidPointer) {
    const char* source = "fn main() -> i32 { var x: i32 = 10; var p: *i32 = &x; return *p; }";

    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* p = comp_unit.createParser(file_id);
    ASTNode* root = p->parse();
    TypeChecker tc(comp_unit);
    tc.check(root);
    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    return true;
}
