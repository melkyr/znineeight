#include "test_framework.hpp"
#include "test_compilation_unit.hpp"
#include "mock_emitter.hpp"
#include "type_checker.hpp"
#include <cstdio>
#include <string>

/**
 * @file slice_tests.cpp
 * @brief Integration tests for Zig slices in the RetroZig compiler.
 */

TEST_FUNC(SliceIntegration_Declaration) {
    const char* source =
        "var global_slice: []i32 = undefined;\n"
        "fn foo() void {\n"
        "    var local_slice: []const u8 = undefined;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    Symbol* global_sym = unit.getSymbolTable().lookup("global_slice");
    ASSERT_TRUE(global_sym != NULL);
    ASSERT_EQ(global_sym->symbol_type->kind, TYPE_SLICE);
    ASSERT_EQ(global_sym->symbol_type->as.slice.element_type->kind, TYPE_I32);
    ASSERT_FALSE(global_sym->symbol_type->as.slice.is_const);

    const ASTFnDeclNode* fn = unit.extractFunctionDeclaration("foo");
    ASSERT_TRUE(fn != NULL);

    // We can't easily look up local symbols from here without custom logic,
    // but the pipeline passing is already a good sign.
    return true;
}

TEST_FUNC(SliceIntegration_ParametersAndReturn) {
    const char* source =
        "fn process(s: []i32) []i32 {\n"
        "    return s;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    Symbol* fn_sym = unit.getSymbolTable().lookup("process");
    ASSERT_TRUE(fn_sym != NULL);
    Type* fn_type = fn_sym->symbol_type;
    ASSERT_EQ(fn_type->kind, TYPE_FUNCTION);
    ASSERT_EQ(fn_type->as.function.params->length(), 1);
    ASSERT_EQ((*fn_type->as.function.params)[0]->kind, TYPE_SLICE);
    ASSERT_EQ(fn_type->as.function.return_type->kind, TYPE_SLICE);

    return true;
}

TEST_FUNC(SliceIntegration_IndexingAndLength) {
    const char* source =
        "fn foo(s: []i32) i32 {\n"
        "    var len: usize = s.len;\n"
        "    return s[0];\n"
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
    MockC89Emitter emitter(&unit.getCallSiteLookupTable(), &unit.getSymbolTable());
    std::string emission = emitter.emitExpression(fn->body);

    // Mock emitter for member access handles .len as .len
    // Mock emitter for array access handles slice as slice.ptr[index]
    ASSERT_TRUE(emission.find("s.len") != std::string::npos);
    ASSERT_TRUE(emission.find("s.ptr[0]") != std::string::npos);

    return true;
}

TEST_FUNC(SliceIntegration_SlicingArrays) {
    const char* source =
        "var arr: [10]i32 = undefined;\n"
        "fn foo() void {\n"
        "    var s1 = arr[0..5];\n"
        "    var s2 = arr[5..];\n"
        "    var s3 = arr[..5];\n"
        "    var s4 = arr[..];\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SliceIntegration_SlicingSlices) {
    const char* source =
        "fn foo(s: []i32) void {\n"
        "    var s1 = s[1..4];\n"
        "    var s2 = s[2..];\n"
        "    var s3 = s[..3];\n"
        "    var s4 = s[..];\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SliceIntegration_SlicingPointers) {
    const char* source =
        "fn foo(ptr: [*]i32) void {\n"
        "    var s1 = ptr[0..10];\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SliceIntegration_ArrayToSliceCoercion) {
    const char* source =
        "fn takeSlice(s: []const i32) void {}\n"
        "fn foo() void {\n"
        "    var arr: [5]i32 = undefined;\n"
        "    takeSlice(arr);\n"
        "    var s: []const i32 = arr;\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}

TEST_FUNC(SliceIntegration_ConstCorrectness) {
    const char* source =
        "fn foo(s: []const i32) void {\n"
        "    s[0] = 42;\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(SliceIntegration_CompileTimeBoundsChecks) {
    const char* source =
        "fn foo() void {\n"
        "    var arr: [10]i32 = undefined;\n"
        "    var s = arr[5..11];\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(SliceIntegration_ManyItemPointerMissingIndices) {
    const char* source =
        "fn foo(ptr: [*]i32) void {\n"
        "    var s = ptr[0..];\n"
        "}\n";

    ASSERT_TRUE(expect_type_checker_abort(source));
    return true;
}

TEST_FUNC(SliceIntegration_ConstPointerToArraySlicing) {
    const char* source =
        "fn foo(ptr: *const [10]i32) void {\n"
        "    var s = ptr[0..5];\n"
        "    // s should be []const i32\n"
        "    // s[0] = 1; // would be error\n"
        "}\n";

    ArenaAllocator arena(1024 * 1024);
    StringInterner interner(arena);
    TestCompilationUnit unit(arena, interner);

    u32 file_id = unit.addSource("test.zig", source);
    if (!unit.performTestPipeline(file_id)) {
        unit.getErrorHandler().printErrors();
        return false;
    }

    return true;
}
