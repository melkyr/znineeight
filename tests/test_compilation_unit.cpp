#include "test_framework.hpp"
#include "compilation_unit.hpp"
#include "memory.hpp"
#include "string_interner.hpp"
#include "parser.hpp"
#include "test_utils.hpp"
#include "ast.hpp"

TEST_FUNC(compilation_unit_creation) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", "const x: i32 = 42;");
    Parser* parser = unit.createParser(file_id);
    ASSERT_TRUE(parser != NULL);
    return true;
}

TEST_FUNC(compilation_unit_var_decl) {
    ArenaAllocator arena(4096);
    StringInterner interner(arena);
    const char* source = "const x: i32 = 42;";
    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* root = parser->parse();
    ASSERT_TRUE(root != NULL);
    ASSERT_EQ(root->type, NODE_BLOCK_STMT);
    ASSERT_EQ(root->as.block_stmt.statements->length(), 1);

    ASTNode* var_decl_node = (*root->as.block_stmt.statements)[0];
    ASSERT_EQ(var_decl_node->type, NODE_VAR_DECL);
    ASSERT_EQ(strcmp(var_decl_node->as.var_decl->name, "x"), 0);
    return true;
}
