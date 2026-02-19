#include "test_framework.hpp"
#include "test_utils.hpp"
#include "compilation_unit.hpp"
#include "type_checker.hpp"
#include "generic_catalogue.hpp"
#include "platform.hpp"

// Test that the module name is correctly derived from the filename.
TEST_FUNC(Task156_ModuleDerivation) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    unit.addSource("src/main.zig", "fn main() void {}");
    ASSERT_STREQ("main", unit.getCurrentModule());

    unit.addSource("lib/utils.zig", "fn util() void {}");
    ASSERT_STREQ("utils", unit.getCurrentModule());

    return true;
}

// Test that AST nodes have the correct module assigned.
TEST_FUNC(Task156_ASTNodeModule) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", "var x: i32 = 0;");
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    ASSERT_STREQ("test", ast->module);
    // Check a child node too
    if (ast->type == NODE_BLOCK_STMT && ast->as.block_stmt.statements->length() > 0) {
        ASTNode* first_stmt = (*ast->as.block_stmt.statements)[0];
        ASSERT_STREQ("test", first_stmt->module);
    }

    return true;
}

// Test enhanced generic instantiation detection with parameter metadata.
TEST_FUNC(Task156_EnhancedGenericDetection) {
    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    CompilationUnit unit(arena, interner);
    unit.injectRuntimeSymbols();

    const char* source =
        "fn generic(comptime T: type, comptime n: i32) void {}\n"
        "fn main() void { generic(i32, 10); }";

    u32 file_id = unit.addSource("main.zig", source);
    Parser* parser = unit.createParser(file_id);
    ASTNode* ast = parser->parse();

    TypeChecker checker(unit);
    checker.check(ast);

    GenericCatalogue& catalogue = unit.getGenericCatalogue();
    ASSERT_EQ(catalogue.count(), 1);

    const DynamicArray<GenericInstantiation>* insts = catalogue.getInstantiations();
    const GenericInstantiation& inst = (*insts)[0];

    ASSERT_STREQ("generic", inst.function_name);
    ASSERT_EQ(inst.param_count, 2);
    ASSERT_STREQ("main", inst.module);
    ASSERT_TRUE(inst.is_explicit);

    // Param 0: i32 (Type)
    ASSERT_EQ((*inst.params)[0].kind, GENERIC_PARAM_TYPE);
    ASSERT_TRUE((*inst.params)[0].type_value != NULL);
    char type_name_buf[64];
    typeToString((*inst.params)[0].type_value, type_name_buf, sizeof(type_name_buf));
    ASSERT_STREQ("i32", type_name_buf);

    // Param 1: 10 (Comptime Int)
    ASSERT_EQ((*inst.params)[1].kind, GENERIC_PARAM_COMPTIME_INT);
    ASSERT_EQ((*inst.params)[1].int_value, 10);

    return true;
}

// Test for internal error code
TEST_FUNC(Task156_InternalErrorCode) {
    ASSERT_EQ((int)ERR_INTERNAL_ERROR, 5001);
    return true;
}
