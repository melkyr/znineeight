#include "test_declarations.hpp"
#include "test_compilation_unit.hpp"
#include "type_checker.hpp"

TEST_FUNC(StringLiteralCoercion_Assignment) {
    const char* source =
        "fn foo() void {\n"
        "    var slice: []const u8 = \"hello\";\n"
        "    _ = slice;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    // Verify it was actually coerced to a slice node
    const ASTVarDeclNode* vd = unit.extractVariableDeclaration("slice");
    if (!vd || !vd->initializer || vd->initializer->type != NODE_ARRAY_SLICE) {
        printf("FAIL: Expected NODE_ARRAY_SLICE for string coercion\n");
        return false;
    }

    return true;
}

TEST_FUNC(StringLiteralCoercion_Argument) {
    const char* source =
        "fn takesSlice(s: []const u8) usize {\n"
        "    return s.len;\n"
        "}\n"
        "fn foo() void {\n"
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

    const ASTNode* call = unit.extractFunctionCall("takesSlice");
    if (!call || !call->as.function_call->args || (*call->as.function_call->args)[0]->type != NODE_ARRAY_SLICE) {
        printf("FAIL: Expected NODE_ARRAY_SLICE for argument coercion\n");
        return false;
    }

    return true;
}

TEST_FUNC(StringLiteralCoercion_Return) {
    const char* source =
        "fn foo() []const u8 {\n"
        "    return \"abc\";\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    // Find return statement in body
    ASTNode* body = fn->body;
    ASTNode* ret = (*body->as.block_stmt.statements)[0];
    if (ret->type != NODE_RETURN_STMT || ret->as.return_stmt.expression->type != NODE_ARRAY_SLICE) {
        printf("FAIL: Expected NODE_ARRAY_SLICE for return coercion\n");
        return false;
    }

    return true;
}

TEST_FUNC(StringLiteralCoercion_NonConstRejection) {
    const char* source =
        "fn foo() void {\n"
        "    var slice: []u8 = \"hello\";\n"
        "    _ = slice;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(ImplicitReturn_ErrorVoid) {
    const char* source =
        "const MyError = error{OutOfMemory};\n"
        "fn foo() MyError!void {\n"
        "}\n"
        "fn bar(cond: bool) MyError!void {\n"
        "    if (cond) return;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    return unit.performTestPipeline(file_id);
}

TEST_FUNC(ImplicitReturn_VoidSuccess) {
    const char* source =
        "fn foo() void {\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    return unit.performTestPipeline(file_id);
}

TEST_FUNC(ImplicitReturn_MissingValueRejection) {
    const char* source =
        "fn foo() i32 {\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(NullPointerAnalyzer_SliceSafe) {
    const char* source =
        "fn getFirst(s: []const u8) u8 {\n"
        "    return s[0];\n"
        "}\n"
        "fn getPtr(s: []const u8) [*]const u8 {\n"
        "    return s.ptr;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);
    unit.getOptions().enable_null_pointer_analysis = true;

    u32 file_id = unit.addSource("test.zig", source);
    return unit.performTestPipeline(file_id);
}
