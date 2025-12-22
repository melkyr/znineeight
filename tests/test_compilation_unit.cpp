#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "ast.hpp"
#include "parser.hpp"

TEST_FUNC(compilation_unit_creation) {
    const char* source = "const x: i32 = 42;";
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);
    Parser parser = unit.createParser(file_id);

    ASSERT_TRUE(parser.peek().type == TOKEN_CONST);

    return true;
}

TEST_FUNC(compilation_unit_var_decl) {
    const char* source = "const y: i32 = 100;";
    ArenaAllocator arena(1024);
    StringInterner interner(arena);

    Parser parser = create_parser_for_test(source, arena, interner);
    ASTNode* decl = parser.parseVarDecl();

    ASSERT_TRUE(decl != NULL);
    ASSERT_TRUE(decl->type == NODE_VAR_DECL);
    ASSERT_TRUE(decl->as.var_decl->is_const);

    return true;
}
