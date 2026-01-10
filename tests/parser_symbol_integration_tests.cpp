#include "test_framework.hpp"
#include "test_utils.hpp"
#include "parser.hpp"
#include "compilation_unit.hpp"
#include "symbol_table.hpp"
#include "type_system.hpp"

TEST_FUNC(Parser_VarDecl_InsertsSymbolCorrectly) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();

    const char* source = "var my_var: i32 = 123;";
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);

    ASTNode* decl_node = parser->parseVarDecl();
    ASSERT_TRUE(decl_node != NULL);

    // After parsing, the symbol should exist in the table.
    Symbol* found_symbol = table.lookup("my_var");
    ASSERT_TRUE(found_symbol != NULL);
    ASSERT_EQ(found_symbol->kind, SYMBOL_VARIABLE);
    ASSERT_TRUE(found_symbol->symbol_type != NULL);
    ASSERT_EQ(found_symbol->symbol_type->kind, TYPE_I32);

    return true;
}

TEST_FUNC(Parser_NestedBlocks_AndShadowing) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();

    // In this source, the inner 'x' (bool) shadows the outer 'x' (i32).
    const char* source = "{ var x: i32 = 1; { var x: bool = false; } }";
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);

    ASTNode* block_node = parser->parseStatement();
    ASSERT_TRUE(block_node != NULL);

    // After parsing the entire block, we should be back in the global scope,
    // so 'x' should not be found at all.
    Symbol* symbol_after = table.lookup("x");
    ASSERT_TRUE(symbol_after == NULL);

    return true;
}

TEST_FUNC(Parser_SymbolDoesNotLeakFromInnerScope) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();

    const char* source = "{ var a: i32 = 1; { var b: bool = true; } }";
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);

    ASTNode* block_node = parser->parseStatement();
    ASSERT_TRUE(block_node != NULL);

    // After parsing, 'a' and 'b' should not be in the global scope.
    ASSERT_TRUE(table.lookup("a") == NULL);
    ASSERT_TRUE(table.lookup("b") == NULL);

    return true;
}

TEST_FUNC(Parser_FnDecl_AndScopeManagement) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    CompilationUnit comp_unit(arena, interner);
    SymbolTable& table = comp_unit.getSymbolTable();

    const char* source = "fn my_func() -> void { var local: i32 = 1; }";
    u32 file_id = comp_unit.addSource("test.zig", source);
    Parser* parser = comp_unit.createParser(file_id);

    // The global scope should be level 1.
    ASSERT_EQ(table.getCurrentScopeLevel(), 1);

    ASTNode* decl_node = parser->parseFnDecl();
    ASSERT_TRUE(decl_node != NULL);

    // After parsing, the scope level should have returned to global.
    ASSERT_EQ(table.getCurrentScopeLevel(), 1);

    // The function symbol should exist in the global scope.
    Symbol* func_symbol = table.lookup("my_func");
    ASSERT_TRUE(func_symbol != NULL);
    ASSERT_EQ(func_symbol->kind, SYMBOL_FUNCTION);

    // The local variable should NOT exist in the global scope.
    Symbol* local_symbol = table.lookup("local");
    ASSERT_TRUE(local_symbol == NULL);

    return true;
}

TEST_FUNC(Parser_VarDecl_DetectsDuplicateSymbol) {
    // Wrap the declarations in a block so they are parsed as a single statement.
    const char* source = "{ var x: i32 = 1; var x: bool = true; }";

    // This test needs to run in a separate process because it's expected to abort.
    ASSERT_TRUE(expect_statement_parser_abort(source));

    return true;
}
