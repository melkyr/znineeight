#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "parser.hpp"
#include "lexer.hpp"

TEST_FUNC(compilation_unit_creation) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    const char* source = "const x: i32 = 42;";
    u32 file_id = unit.addSource("test.zig", source);

    Parser* parser = unit.createParser(file_id);

    ASSERT_TRUE(!parser->is_at_end());
    ASSERT_TRUE(parser->peek().type == TOKEN_CONST);
    return true;
}

TEST_FUNC(compilation_unit_var_decl) {
    ArenaAllocator arena(8192);
    StringInterner interner(arena);
    const char* source = "const x: i32 = 42;";

    ParserTestContext ctx(source, arena, interner);
    Parser* parser = ctx.getParser();

    ASTNode* node = parser->parseVarDecl();
    ASSERT_TRUE(node != NULL);
    ASSERT_EQ(node->type, NODE_VAR_DECL);
    return true;
}
