#include "type_system.hpp"
#include "error_handler.hpp"
#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "ast.hpp"

// This test function is for cases that should pass without any errors.
TEST_FUNC(TypeChecker_PointerArithmetic_ValidCases_ExplicitTyping) {
    {
        const char* source = "fn main() { var p: *i32; var i: usize; var res: *i32 = p + i; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();

        TypeChecker tc(comp_unit);
        tc.check(root);

        ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    }

    {
        const char* source = "fn main() { var p: *i32; var i: usize; var res: *i32 = i + p; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();

        TypeChecker tc(comp_unit);
        tc.check(root);

        ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    }

    {
        const char* source = "fn main() { var p: *i32; var i: usize; var res: *i32 = p - i; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();

        TypeChecker tc(comp_unit);
        tc.check(root);

        ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    }

    {
        const char* source = "fn main() { var p1: *i32; var p2: *i32; var res: isize = p1 - p2; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();

        TypeChecker tc(comp_unit);
        tc.check(root);

        ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());
    }

    return true;
}

// This test function is for cases that should fail with a type mismatch error.
TEST_FUNC(TypeChecker_PointerArithmetic_InvalidCases_ExplicitTyping) {
    // Test: pointer + pointer -> error
    {
        const char* source = "fn main() { var p1: *i32; var p2: *i32; var res: *i32 = p1 + p2; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_POINTER_ARITHMETIC_INVALID_OPERATOR);
    }

    // Test: pointer * integer -> error
    {
        const char* source = "fn main() { var p: *i32; var i: usize; var res: *i32 = p * i; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_POINTER_ARITHMETIC_INVALID_OPERATOR);
    }

    // Test: pointer / integer -> error
    {
        const char* source = "fn main() { var p: *i32; var i: usize; var res: *i32 = p / i; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_POINTER_ARITHMETIC_INVALID_OPERATOR);
    }

    // Test: pointer % integer -> error
    {
        const char* source = "fn main() { var p: *i32; var i: usize; var res: *i32 = p % i; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_POINTER_ARITHMETIC_INVALID_OPERATOR);
    }

    // Test: pointer - pointer (mismatched types) -> error
    {
        const char* source = "fn main() { var p1: *i32; var p2: *u8; var res: isize = p1 - p2; }";
        ArenaAllocator arena(1024 * 1024);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_POINTER_SUBTRACTION_INCOMPATIBLE);
    }

    return true;
}
