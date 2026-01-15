#include "type_system.hpp"
#include "error_handler.hpp"
#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "ast.hpp"

// Helper function to get the type of the `res` variable in a source snippet
static Type* get_res_var_type(const char* source) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* p = comp_unit.createParser(file_id);
    ASTNode* root = p->parse();

    TypeChecker tc(comp_unit);
    tc.check(root);

    if (comp_unit.getErrorHandler().hasErrors()) {
        return NULL;
    }

    Symbol* res_symbol = comp_unit.getSymbolTable().lookup("res");
    if (res_symbol) {
        return res_symbol->symbol_type;
    }
    return NULL;
}

TEST_FUNC(TypeChecker_PointerArithmetic_ValidCases) {
    // Test: pointer + integer -> pointer
    {
        const char* source = "fn main() -> void { var p: *i32; var i: i32; var res = p + i; }";
        Type* result_type = get_res_var_type(source);
        ASSERT_TRUE(result_type != NULL);
        if (!result_type) return false;
        ASSERT_TRUE(result_type->kind == TYPE_POINTER);
        ASSERT_TRUE(result_type->as.pointer.base->kind == TYPE_I32);
    }

    // Test: integer + pointer -> pointer
    {
        const char* source = "fn main() -> void { var p: *i32; var i: i32; var res = i + p; }";
        Type* result_type = get_res_var_type(source);
        ASSERT_TRUE(result_type != NULL);
        if (!result_type) return false;
        ASSERT_TRUE(result_type->kind == TYPE_POINTER);
        ASSERT_TRUE(result_type->as.pointer.base->kind == TYPE_I32);
    }

    // Test: pointer - integer -> pointer
    {
        const char* source = "fn main() -> void { var p: *i32; var i: i32; var res = p - i; }";
        Type* result_type = get_res_var_type(source);
        ASSERT_TRUE(result_type != NULL);
        if (!result_type) return false;
        ASSERT_TRUE(result_type->kind == TYPE_POINTER);
        ASSERT_TRUE(result_type->as.pointer.base->kind == TYPE_I32);
    }

    // Test: pointer - pointer -> isize
    {
        const char* source = "fn main() -> void { var p1: *i32; var p2: *i32; var res = p1 - p2; }";
        Type* result_type = get_res_var_type(source);
        ASSERT_TRUE(result_type != NULL);
        if (!result_type) return false;
        ASSERT_TRUE(result_type->kind == TYPE_ISIZE);
    }

    return true;
}

TEST_FUNC(TypeChecker_PointerArithmetic_InvalidCases) {
    // Test: pointer + pointer -> error
    {
        const char* source = "fn main() -> void { var p1: *i32; var p2: *i32; var res = p1 + p2; }";
        ArenaAllocator arena(16384);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    // Test: pointer * integer -> error
    {
        const char* source = "fn main() -> void { var p: *i32; var i: i32; var res = p * i; }";
        ArenaAllocator arena(16384);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    // Test: pointer / integer -> error
    {
        const char* source = "fn main() -> void { var p: *i32; var i: i32; var res = p / i; }";
        ArenaAllocator arena(16384);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    // Test: pointer % integer -> error
    {
        const char* source = "fn main() -> void { var p: *i32; var i: i32; var res = p % i; }";
        ArenaAllocator arena(16384);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    // Test: pointer - pointer (mismatched types) -> error
    {
        const char* source = "fn main() -> void { var p1: *i32; var p2: *u8; var res = p1 - p2; }";
        ArenaAllocator arena(16384);
        StringInterner interner(arena);
        CompilationUnit comp_unit(arena, interner);
        u32 file_id = comp_unit.addSource("test.zig", source);
        Parser* p = comp_unit.createParser(file_id);
        ASTNode* root = p->parse();
        TypeChecker tc(comp_unit);
        tc.check(root);
        ASSERT_TRUE(comp_unit.getErrorHandler().hasErrors());
        ASSERT_EQ(comp_unit.getErrorHandler().getErrors()[0].code, ERR_TYPE_MISMATCH);
    }

    return true;
}
