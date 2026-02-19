#include "test_framework.hpp"
#include "parser.hpp"
#include "type_checker.hpp"
#include "compilation_unit.hpp"
#include "test_utils.hpp"

TEST_FUNC(TypeChecker_FunctionPointer_Coercion) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo(x: i32) void {}\n"
        "const fp: fn(i32) void = foo;";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_Mismatch) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo(x: i32) void {}\n"
        "const fp: fn(bool) void = foo;";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    // Should fail due to signature mismatch
    ASSERT_FALSE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_Null) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "var fp: fn(i32) void = null;";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_Parameter) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn call_it(fp: fn(i32) void, val: i32) void {\n"
        "    fp(val);\n"
        "}\n"
        "fn foo(x: i32) void {}\n"
        "fn bar() void {\n"
        "    call_it(foo, 42);\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_ReturnCall) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo(x: i32) void {}\n"
        "fn getFP() fn(i32) void { return foo; }\n"
        "fn bar() void {\n"
        "    getFP()(42);\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_ArrayCall) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo(x: i32) void {}\n"
        "var fps: [1]fn(i32) void = [1]fn(i32) void { foo };\n"
        "fn bar() void {\n"
        "    fps[0](42);\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}

TEST_FUNC(TypeChecker_FunctionPointer_ComplexCall) {
    ArenaAllocator arena(1024 * 1024);
    ArenaLifetimeGuard guard(arena);
    StringInterner interner(arena);

    const char* source =
        "fn foo(x: i32) void {}\n"
        "fn bar(x: i32) void {}\n"
        "fn call(cond: bool) void {\n"
        "    (if (cond) foo else bar)(42);\n"
        "}";

    CompilationUnit unit(arena, interner);
    u32 file_id = unit.addSource("test.zig", source);

    ASSERT_TRUE(unit.performFullPipeline(file_id));

    return true;
}
