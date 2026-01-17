#include "test_framework.hpp"
#include "test_utils.hpp"
#include "type_checker.hpp"
#include "symbol_table.hpp"

TEST_FUNC(SymbolFlags_GlobalVariable) {
    ArenaAllocator arena(16384);
    StringInterner interner(arena);
    const char* source = "var global_x: i32 = 42;";
    ParserTestContext ctx(source, arena, interner);
    TypeChecker type_checker(ctx.getCompilationUnit());

    ASTNode* root = ctx.getParser()->parse();
    ASSERT_TRUE(root != NULL);

    type_checker.check(root);

    Symbol* sym = ctx.getCompilationUnit().getSymbolTable().lookup("global_x");
    ASSERT_TRUE(sym != NULL);

    // Check flags - use literal values for extra safety during first test run
    // SYMBOL_FLAG_GLOBAL = 8, SYMBOL_FLAG_LOCAL = 1
    ASSERT_TRUE(sym->flags & SYMBOL_FLAG_GLOBAL);
    ASSERT_FALSE(sym->flags & SYMBOL_FLAG_LOCAL);

    return true;
}

TEST_FUNC(SymbolFlags_SymbolBuilder) {
    ArenaAllocator arena(16384);
    Symbol sym = SymbolBuilder(arena)
        .withName("test")
        .ofType(SYMBOL_VARIABLE)
        .withFlags(SYMBOL_FLAG_LOCAL | SYMBOL_FLAG_PARAM)
        .build();

    ASSERT_TRUE(sym.flags & SYMBOL_FLAG_LOCAL);
    ASSERT_TRUE(sym.flags & SYMBOL_FLAG_PARAM);
    ASSERT_FALSE(sym.flags & SYMBOL_FLAG_GLOBAL);

    return true;
}
