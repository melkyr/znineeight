#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "type_checker.hpp"

TEST_FUNC(Task9_8_StringLiteralCoercion) {
    const char* source =
        "fn takesSlice(s: []const u8) usize { return s.len; }\n"
        "pub fn main() void {\n"
        "    var slice: []const u8 = \"hello\";\n"
        "    _ = takesSlice(\"world\");\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Verify assignment coercion
    const ASTVarDeclNode* var_decl = unit.extractVariableDeclaration("slice");
    ASSERT_TRUE(var_decl != NULL);
    ASSERT_TRUE(var_decl->initializer != NULL);
    // Coercion should wrap string literal in a NODE_ARRAY_SLICE
    ASSERT_EQ(var_decl->initializer->type, NODE_ARRAY_SLICE);

    // Verify call coercion
    const ASTNode* call = unit.extractFunctionCall("takesSlice");
    ASSERT_TRUE(call != NULL);
    ASSERT_TRUE(call->as.function_call->args != NULL);
    ASSERT_EQ(call->as.function_call->args->length(), 1);
    ASSERT_EQ((*call->as.function_call->args)[0]->type, NODE_ARRAY_SLICE);

    return true;
}

TEST_FUNC(Task9_8_ImplicitReturnErrorVoid) {
    const char* source =
        "const MyError = error { Foo };\n"
        "fn foo() MyError!void {\n"
        "    // no explicit return\n"
        "}\n"
        "pub fn main() void {\n"
        "    foo() catch {};\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Verify emission includes return {0};
    ASSERT_TRUE(unit.validateRealFunctionEmission("foo",
        "static struct ErrorUnion_void zF_2_foo(void) {\n"
        "    {\n"
        "        struct ErrorUnion_void __implicit_ret = {0};\n"
        "        return __implicit_ret;\n"
        "    }\n"
        "}"));

    return true;
}

TEST_FUNC(Task9_8_WhileContinueExpr) {
    const char* source =
        "pub fn sum_up_to(n: u32) u32 {\n"
        "    var i: u32 = 0;\n"
        "    var total: u32 = 0;\n"
        "    while (i < n) : (i += 1) {\n"
        "        total += i;\n"
        "    }\n"
        "    return total;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Verify emission includes i += 1 at the end of the loop body
    ASSERT_TRUE(unit.validateRealFunctionEmission("sum_up_to",
        "unsigned int zF_0_sum_up_to(unsigned int n) {\n"
        "    unsigned int i;\n"
        "    unsigned int total;\n"
        "    i = 0;\n"
        "    total = 0;\n"
        "    __loop_0_start: ;\n"
        "    if (!(i < n)) goto __loop_0_end;\n"
        "    {\n"
        "        total += i;\n"
        "    }\n"
        "    __loop_0_continue: ;\n"
        "    (void)(i += 1);\n"
        "    goto __loop_0_start;\n"
        "    __loop_0_end: ;\n"
        "    return total;\n"
        "}"));

    return true;
}
