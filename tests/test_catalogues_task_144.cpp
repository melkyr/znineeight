#include "test_framework.hpp"
#include "catch_expression_catalogue.hpp"
#include "orelse_expression_catalogue.hpp"
#include "memory.hpp"
#include "type_system.hpp"

TEST_FUNC(CatchExpressionCatalogue_Basic) {
    ArenaAllocator arena(1024 * 1024);
    CatchExpressionCatalogue cat(arena);

    ASSERT_EQ(0, cat.count());

    SourceLocation loc;
    loc.file_id = 1;
    loc.line = 5;
    loc.column = 10;
    Type* error_type = (Type*)arena.alloc(sizeof(Type));
    Type* handler_type = (Type*)arena.alloc(sizeof(Type));
    Type* result_type = (Type*)arena.alloc(sizeof(Type));

    cat.addCatchExpression(loc, "assignment", error_type, handler_type, result_type, "err", 0, false);
    ASSERT_EQ(1, cat.count());

    const DynamicArray<CatchExpressionInfo>* exprs = cat.getCatchExpressions();
    ASSERT_EQ(loc.line, (*exprs)[0].location.line);
    ASSERT_STREQ("assignment", (*exprs)[0].context_type);
    ASSERT_EQ(error_type, (*exprs)[0].error_type);
    ASSERT_STREQ("err", (*exprs)[0].error_param_name);
    ASSERT_EQ(0, (*exprs)[0].chain_index);
    ASSERT_FALSE((*exprs)[0].is_chained);

    return true;
}

TEST_FUNC(CatchExpressionCatalogue_Chaining) {
    ArenaAllocator arena(1024 * 1024);
    CatchExpressionCatalogue cat(arena);

    SourceLocation loc1;
    loc1.file_id = 1;
    loc1.line = 5;
    loc1.column = 10;

    SourceLocation loc2;
    loc2.file_id = 1;
    loc2.line = 15;
    loc2.column = 10;

    Type* t = (Type*)arena.alloc(sizeof(Type));

    cat.addCatchExpression(loc1, "assignment", t, t, t, "err1", 0, true);
    cat.addCatchExpression(loc2, "assignment", t, t, t, "err2", 1, true);

    ASSERT_EQ(2, cat.count());
    const DynamicArray<CatchExpressionInfo>* exprs = cat.getCatchExpressions();
    ASSERT_EQ(0, (*exprs)[0].chain_index);
    ASSERT_TRUE((*exprs)[0].is_chained);
    ASSERT_EQ(1, (*exprs)[1].chain_index);
    ASSERT_TRUE((*exprs)[1].is_chained);

    return true;
}

TEST_FUNC(OrelseExpressionCatalogue_Basic) {
    ArenaAllocator arena(1024 * 1024);
    OrelseExpressionCatalogue cat(arena);

    ASSERT_EQ(0, cat.count());

    SourceLocation loc;
    loc.file_id = 1;
    loc.line = 5;
    loc.column = 10;

    Type* t = (Type*)arena.alloc(sizeof(Type));

    cat.addOrelseExpression(loc, "variable_decl", t, t, t);
    ASSERT_EQ(1, cat.count());

    const DynamicArray<OrelseExpressionInfo>* exprs = cat.getOrelseExpressions();
    ASSERT_STREQ("variable_decl", (*exprs)[0].context_type);
    ASSERT_EQ(loc.line, (*exprs)[0].location.line);

    return true;
}
