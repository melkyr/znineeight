#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "symbol_table.hpp"

TEST_FUNC(TypeChecker_RejectSlice) {
    const char* source = "var my_slice: []u8;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(TypeChecker_AcceptsValidArrayDeclaration) {
    const char* source = "var my_array: [16]i32;";
    ArenaAllocator arena(8192);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);

    // The root node from parse() is a NODE_BLOCK_STMT containing the var decl
    ASTNode* ast = parser->parse();
    ASSERT_EQ(ast->type, NODE_BLOCK_STMT);
    ASSERT_EQ(ast->as.block_stmt.statements->length(), 1);
    ASTNode* var_decl_node = (*ast->as.block_stmt.statements)[0];
    ASSERT_EQ(var_decl_node->type, NODE_VAR_DECL);

    TypeChecker type_checker(comp_unit);

    // Manually manage the global scope to inspect symbols after checking.
    // The TypeChecker's check() method would normally enter and then exit the scope.
    comp_unit.getSymbolTable().enterScope();

    // Visit just the variable declaration, not the whole block,
    // to avoid the automatic exitScope().
    type_checker.visit(var_decl_node);

    ASSERT_FALSE(comp_unit.getErrorHandler().hasErrors());

    Symbol* sym = comp_unit.getSymbolTable().lookup("my_array");
    ASSERT_TRUE(sym != NULL);
    ASSERT_TRUE(sym->symbol_type != NULL);
    ASSERT_EQ(sym->symbol_type->kind, TYPE_ARRAY);
    ASSERT_EQ(sym->symbol_type->as.array.size, 16);
    ASSERT_TRUE(sym->symbol_type->as.array.element_type != NULL);
    ASSERT_EQ(sym->symbol_type->as.array.element_type->kind, TYPE_I32);

    comp_unit.getSymbolTable().exitScope();

    return true;
}

TEST_FUNC(TypeChecker_RejectNonConstantArraySize) {
    const char* source = "var x: i32 = 8; var my_array: [x]u8;";
    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}
