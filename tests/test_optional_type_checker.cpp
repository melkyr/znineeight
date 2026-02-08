#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"

TEST_FUNC(TypeChecker_OptionalType) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    const char* source = "var x: ?i32 = null;";
    ParserTestContext context(source, arena, interner);
    Parser* parser = context.getParser();
    ASTNode* root = parser->parse();

    TypeChecker checker(context.getCompilationUnit());
    checker.check(root);

    // Find the variable declaration
    ASTNode* var_decl_node = (*root->as.block_stmt.statements)[0];
    ASSERT_EQ(NODE_VAR_DECL, var_decl_node->type);

    Symbol* sym = context.getCompilationUnit().getSymbolTable().lookup("x");
    ASSERT_TRUE(sym != NULL);
    ASSERT_TRUE(sym->symbol_type != NULL);
    ASSERT_EQ(TYPE_OPTIONAL, sym->symbol_type->kind);
    ASSERT_EQ(TYPE_I32, sym->symbol_type->as.optional.payload->kind);

    return true;
}
